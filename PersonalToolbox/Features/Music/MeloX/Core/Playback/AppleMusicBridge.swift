import Foundation
import MusicKit

/// MusicKit bridge: catalog search + ApplicationMusicPlayer (needs Apple Music membership).
@MainActor
final class AppleMusicBridge {
    static let shared = AppleMusicBridge()

    enum BridgeError: LocalizedError {
        case notAuthorized
        case denied
        case restricted
        case noMatch(title: String, artist: String)
        case playFailed(String)
        case subscriptionRequired

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "尚未获得 Apple Music 权限，请允许访问媒体与 Apple Music。"
            case .denied:
                return "Apple Music 权限被拒绝。请到 设置 → 本 App 中开启媒体与 Apple Music。"
            case .restricted:
                return "设备策略限制了 Apple Music 访问。"
            case .noMatch(let title, let artist):
                let q = [title, artist].filter { !$0.isEmpty }.joined(separator: " - ")
                return "在 Apple Music 曲库中未找到「\(q)」。"
            case .playFailed(let msg):
                return "Apple Music 播放失败：\(msg)"
            case .subscriptionRequired:
                return "需要有效的 Apple Music 会员才能播放曲库。"
            }
        }
    }

    private let player = ApplicationMusicPlayer.shared
    private let matchCache = AppleMusicMatchCache.shared
    private(set) var isActive = false
    private(set) var matchedTitle: String?
    private(set) var matchedArtist: String?
    private(set) var matchedMusicItemID: String?
    private var activeDuration: TimeInterval = 0

    private var pollTask: Task<Void, Never>?
    /// (isPlaying, position, duration)
    var onPlaybackState: ((Bool, TimeInterval, TimeInterval) -> Void)?
    var onEnded: (() -> Void)?

    var isAuthorized: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    var authorizationStatus: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    /// Last known subscription capability (refresh via `refreshSubscriptionStatus`).
    private(set) var canPlayCatalogContent = false
    private(set) var subscriptionChecked = false

    func ensureAuthorized() async throws {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return
        case .denied:
            throw BridgeError.denied
        case .restricted:
            throw BridgeError.restricted
        case .notDetermined:
            let status = await MusicAuthorization.request()
            guard status == .authorized else {
                if status == .denied { throw BridgeError.denied }
                throw BridgeError.notAuthorized
            }
        @unknown default:
            throw BridgeError.notAuthorized
        }
    }

    /// Request system permission (for settings "连接" button).
    @discardableResult
    func requestAuthorization() async -> MusicAuthorization.Status {
        if MusicAuthorization.currentStatus == .notDetermined {
            return await MusicAuthorization.request()
        }
        return MusicAuthorization.currentStatus
    }

    func refreshSubscriptionStatus() async {
        do {
            try await ensureAuthorized()
            let sub = try await MusicSubscription.current
            canPlayCatalogContent = sub.canPlayCatalogContent
            subscriptionChecked = true
        } catch {
            canPlayCatalogContent = false
            subscriptionChecked = true
        }
    }

    /// Search catalog for match picker (up to 8 candidates).
    func searchCandidates(title: String, artist: String, limit: Int = 8) async throws -> [AppleMusicCandidate] {
        try await ensureAuthorized()
        let term = searchTerm(title: title, artist: artist)
        guard !term.isEmpty else { return [] }

        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
        request.limit = limit
        let response = try await request.response()
        return response.songs.map { AppleMusicCandidate(song: $0) }
    }

    /// Free-text catalog search (Search tab dual-source).
    func searchCatalog(query: String, limit: Int = 20) async throws -> [AppleMusicCandidate] {
        try await ensureAuthorized()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
        request.limit = limit
        let response = try await request.response()
        return response.songs.map { AppleMusicCandidate(song: $0) }
    }

    /// Search Apple Music catalog and play via ApplicationMusicPlayer.
    @discardableResult
    func playMatching(
        title: String,
        artist: String,
        neteaseSongID: Int? = nil
    ) async throws -> MusicKit.Song {
        try await ensureAuthorized()

        if let neteaseSongID,
           let cached = matchCache.musicItemID(forNeteaseSongID: neteaseSongID),
           let song = try await fetchSong(idRaw: cached) {
            try await play(song: song)
            return song
        }

        let term = searchTerm(title: title, artist: artist)
        guard !term.isEmpty else {
            throw BridgeError.noMatch(title: title, artist: artist)
        }

        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
        request.limit = 12
        let response = try await request.response()
        guard let song = bestMatch(in: response.songs, title: title, artist: artist) else {
            throw BridgeError.noMatch(title: title, artist: artist)
        }

        try await play(song: song)
        if let neteaseSongID {
            matchCache.store(neteaseSongID: neteaseSongID, musicItemID: song.id.rawValue)
        }
        return song
    }

    /// Play a specific catalog id (match picker / cached choice).
    @discardableResult
    func playMusicItemID(_ idRaw: String, neteaseSongID: Int? = nil) async throws -> MusicKit.Song {
        try await ensureAuthorized()
        guard let song = try await fetchSong(idRaw: idRaw) else {
            throw BridgeError.playFailed("无法加载所选曲目。")
        }
        try await play(song: song)
        if let neteaseSongID {
            matchCache.store(neteaseSongID: neteaseSongID, musicItemID: song.id.rawValue)
        }
        return song
    }

    func pause() {
        guard isActive else { return }
        player.pause()
        onPlaybackState?(false, player.playbackTime, activeDuration)
    }

    func resume() async throws {
        guard isActive else { return }
        do {
            try await player.play()
            onPlaybackState?(true, player.playbackTime, activeDuration)
        } catch {
            throw BridgeError.playFailed(error.localizedDescription)
        }
    }

    func stop() {
        if isActive {
            player.stop()
        }
        isActive = false
        matchedTitle = nil
        matchedArtist = nil
        matchedMusicItemID = nil
        activeDuration = 0
        pollTask?.cancel()
        pollTask = nil
    }

    func seek(to seconds: TimeInterval) {
        guard isActive else { return }
        let maxT = activeDuration > 0 ? activeDuration : seconds
        player.playbackTime = max(0, min(seconds, maxT))
        let playing = player.state.playbackStatus == .playing
        onPlaybackState?(playing, player.playbackTime, activeDuration)
    }

    // MARK: - Private play helpers

    private func play(song: MusicKit.Song) async throws {
        player.stop()
        player.queue = [song]
        do {
            try await player.play()
        } catch {
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("subscription")
                || msg.localizedCaseInsensitiveContains("会员") {
                throw BridgeError.subscriptionRequired
            }
            throw BridgeError.playFailed(msg)
        }

        isActive = true
        matchedTitle = song.title
        matchedArtist = song.artistName
        matchedMusicItemID = song.id.rawValue
        activeDuration = song.duration ?? 0
        startPolling()
        onPlaybackState?(true, 0, activeDuration)
    }

    private func fetchSong(idRaw: String) async throws -> MusicKit.Song? {
        let musicID = MusicItemID(idRaw)
        let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: musicID)
        let response = try await request.response()
        return response.items.first
    }

    private func searchTerm(title: String, artist: String) -> String {
        [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Matching

    private func bestMatch(
        in songs: MusicItemCollection<MusicKit.Song>,
        title: String,
        artist: String
    ) -> MusicKit.Song? {
        let t = normalize(title)
        let a = normalize(artist)
        guard !songs.isEmpty else { return nil }

        var scored: [(MusicKit.Song, Int)] = []
        for song in songs {
            var score = 0
            let st = normalize(song.title)
            let sa = normalize(song.artistName)
            if st == t { score += 50 }
            else if st.contains(t) || t.contains(st) { score += 30 }
            if !a.isEmpty {
                if sa == a { score += 40 }
                else if sa.contains(a) || a.contains(sa) { score += 20 }
                for part in a.split(whereSeparator: { $0 == "/" || $0 == "," || $0 == "&" }) {
                    let p = normalize(String(part))
                    if !p.isEmpty, sa.contains(p) { score += 10 }
                }
            }
            scored.append((song, score))
        }
        scored.sort { $0.1 > $1.1 }
        if let best = scored.first, best.1 >= 20 {
            return best.0
        }
        return songs.first
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var lastPlaying = true
            while !Task.isCancelled {
                guard let self, self.isActive else { break }
                let status = self.player.state.playbackStatus
                let playing = status == .playing
                let position = self.player.playbackTime
                let duration = self.activeDuration
                self.onPlaybackState?(playing, position, duration)

                if lastPlaying,
                   !playing,
                   duration > 1,
                   position >= duration - 1.25 {
                    self.isActive = false
                    self.onEnded?()
                    break
                }
                if status == .stopped, duration > 1, position >= duration - 1.5 {
                    self.isActive = false
                    self.onEnded?()
                    break
                }
                lastPlaying = playing
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }
}
