import AVFoundation
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
        case audioSession(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "尚未获得 Apple Music 权限。请到音乐设置 → Apple Music 点「连接」。"
            case .denied:
                return "Apple Music 权限被拒绝。请到 系统设置 → 本 App → 开启「媒体与 Apple Music」。"
            case .restricted:
                return "设备策略限制了 Apple Music 访问。"
            case .noMatch(let title, let artist):
                let q = [title, artist].filter { !$0.isEmpty }.joined(separator: " - ")
                return "在 Apple Music 曲库中未找到「\(q)」（可换匹配或检查商店地区）。"
            case .playFailed(let msg):
                return "Apple Music 播放失败：\(msg)"
            case .subscriptionRequired:
                return "需要有效的 Apple Music 会员，并在系统「音乐」App 登录同一 Apple ID。"
            case .audioSession(let msg):
                return "无法激活播放音频会话：\(msg)"
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

    /// Last failure detail for UI / diagnostics.
    private(set) var lastErrorDescription: String?

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

    func searchCandidates(title: String, artist: String, limit: Int = 8) async throws -> [AppleMusicCandidate] {
        try await ensureAuthorized()
        let songs = try await searchSongs(title: title, artist: artist, limit: limit)
        return songs.map { AppleMusicCandidate(song: $0) }
    }

    func searchCatalog(query: String, limit: Int = 20) async throws -> [AppleMusicCandidate] {
        try await ensureAuthorized()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
        request.limit = limit
        let response = try await request.response()
        return response.songs.map { AppleMusicCandidate(song: $0) }
    }

    @discardableResult
    func playMatching(
        title: String,
        artist: String,
        neteaseSongID: Int? = nil
    ) async throws -> MusicKit.Song {
        lastErrorDescription = nil
        try await ensureAuthorized()
        // Best-effort only: OSStatus -50 must not block MusicKit play.
        activatePlaybackSessionBestEffort()

        // Cached id first; drop cache if play fails.
        if let neteaseSongID,
           let cached = matchCache.musicItemID(forNeteaseSongID: neteaseSongID) {
            do {
                if let song = try await fetchSong(idRaw: cached) {
                    try await play(song: song)
                    return song
                }
            } catch {
                matchCache.remove(neteaseSongID: neteaseSongID)
                // fall through to search
            }
        }

        let candidates = try await searchSongs(title: title, artist: artist, limit: 12)
        guard let song = bestMatch(in: candidates, title: title, artist: artist) else {
            let err = BridgeError.noMatch(title: title, artist: artist)
            lastErrorDescription = err.localizedDescription
            throw err
        }

        try await play(song: song)
        if let neteaseSongID {
            matchCache.store(neteaseSongID: neteaseSongID, musicItemID: song.id.rawValue)
        }
        return song
    }

    @discardableResult
    func playMusicItemID(_ idRaw: String, neteaseSongID: Int? = nil) async throws -> MusicKit.Song {
        lastErrorDescription = nil
        try await ensureAuthorized()
        activatePlaybackSessionBestEffort()
        guard let song = try await fetchSong(idRaw: idRaw) else {
            let err = BridgeError.playFailed("无法加载所选曲目（id=\(idRaw)）。")
            lastErrorDescription = err.localizedDescription
            throw err
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
        activatePlaybackSessionBestEffort()
        do {
            try await player.play()
            onPlaybackState?(true, player.playbackTime, activeDuration)
        } catch {
            throw mapPlayError(error)
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

    // MARK: - Search

    /// Multi-pass catalog search so Chinese VIP titles still match.
    private func searchSongs(title: String, artist: String, limit: Int) async throws -> [MusicKit.Song] {
        let cleanedTitle = scrubSearchToken(title)
        let cleanedArtist = scrubSearchToken(artist)
        var seen = Set<String>()
        var collected: [MusicKit.Song] = []

        let terms: [String] = {
            var list: [String] = []
            let both = [cleanedTitle, cleanedArtist].filter { !$0.isEmpty }.joined(separator: " ")
            if !both.isEmpty { list.append(both) }
            if !cleanedTitle.isEmpty { list.append(cleanedTitle) }
            // First artist only (网易云 "A / B / C")
            let primaryArtist = cleanedArtist
                .split(whereSeparator: { $0 == "/" || $0 == "," || $0 == "、" || $0 == "&" })
                .map { scrubSearchToken(String($0)) }
                .first { !$0.isEmpty }
            if let primaryArtist, !cleanedTitle.isEmpty {
                list.append("\(cleanedTitle) \(primaryArtist)")
            }
            return list
        }()

        for term in terms {
            guard !term.isEmpty else { continue }
            var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
            request.limit = limit
            do {
                let response = try await request.response()
                for song in response.songs {
                    let key = song.id.rawValue
                    if seen.insert(key).inserted {
                        collected.append(song)
                    }
                }
            } catch {
                // try next term
                lastErrorDescription = error.localizedDescription
                continue
            }
            if collected.count >= 3 { break }
        }

        if collected.isEmpty, let lastErrorDescription {
            throw BridgeError.playFailed("曲库搜索失败：\(lastErrorDescription)")
        }
        return collected
    }

    private func scrubSearchToken(_ raw: String) -> String {
        var s = raw
        // Drop common clutter from Netease titles.
        let patterns = [
            #"\(.*?\)"#, #"（.*?）"#, #"\[.*?\]"#, #"【.*?】"#,
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        for token in ["官方", "动态歌词", "伴奏", "完整版", "Live", "live", "现场"] {
            s = s.replacingOccurrences(of: token, with: " ")
        }
        return s
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Play

    private func play(song: MusicKit.Song) async throws {
        // Songs without playParameters cannot stream for this account/region.
        if song.playParameters == nil {
            let err = BridgeError.playFailed(
                "该曲目当前账号/地区不可流媒体播放（无 playParameters）。请确认 Apple Music 会员与商店地区。"
            )
            lastErrorDescription = err.localizedDescription
            throw err
        }

        activatePlaybackSessionBestEffort()

        // Reset any prior queue state cleanly.
        player.stop()
        player.queue = ApplicationMusicPlayer.Queue(for: [song])

        do {
            try await player.prepareToPlay()
        } catch {
            // prepareToPlay is best-effort; still try play().
            lastErrorDescription = "prepareToPlay: \(error.localizedDescription)"
        }

        do {
            try await player.play()
        } catch {
            // One retry after re-activating session (common after AVPlayer teardown).
            activatePlaybackSessionBestEffort(forceReset: true)
            try? await Task.sleep(nanoseconds: 250_000_000)
            do {
                player.queue = ApplicationMusicPlayer.Queue(for: [song])
                try await player.play()
            } catch {
                let mapped = mapPlayError(error)
                lastErrorDescription = mapped.localizedDescription
                throw mapped
            }
        }

        // Confirm player actually entered a playable state.
        try? await Task.sleep(nanoseconds: 150_000_000)
        let status = player.state.playbackStatus
        if status == .paused || status == .stopped {
            // Some devices need a second play kick.
            try? await player.play()
        }

        isActive = true
        matchedTitle = song.title
        matchedArtist = song.artistName
        matchedMusicItemID = song.id.rawValue
        activeDuration = song.duration ?? 0
        startPolling()
        onPlaybackState?(true, player.playbackTime, activeDuration > 0 ? activeDuration : (song.duration ?? 0))
        lastErrorDescription = nil
    }

    private func mapPlayError(_ error: Error) -> BridgeError {
        let msg = error.localizedDescription
        let lower = msg.lowercased()
        if lower.contains("subscription")
            || lower.contains("not subscribed")
            || msg.contains("会员")
            || lower.contains("permission") {
            return .subscriptionRequired
        }
        if lower.contains("auth") || lower.contains("denied") {
            return .notAuthorized
        }
        return .playFailed(msg)
    }

    /// Configure AVAudioSession for MusicKit. Never throw to callers — OSStatus -50
    /// (paramErr) is common when options clash after AVPlayer teardown; MusicKit can
    /// still play once a simple `.playback` category is applied (or even if setActive fails).
    private func activatePlaybackSessionBestEffort(forceReset: Bool = false) {
        let session = AVAudioSession.sharedInstance()

        if forceReset {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }

        // Mirror AudioPlaybackEngine: simplest API avoids -50 from option combos.
        let attempts: [() throws -> Void] = [
            {
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            },
            {
                try session.setCategory(.playback)
                try session.setActive(true)
            },
            {
                // Last resort: category only, ignore setActive failure.
                try session.setCategory(.playback, mode: .default)
            },
        ]

        for (index, attempt) in attempts.enumerated() {
            do {
                try attempt()
                return
            } catch {
                lastErrorDescription = "audioSession attempt\(index + 1): \(error.localizedDescription)"
                continue
            }
        }
    }

    private func fetchSong(idRaw: String) async throws -> MusicKit.Song? {
        let musicID = MusicItemID(idRaw)
        let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: musicID)
        let response = try await request.response()
        return response.items.first
    }

    // MARK: - Matching

    private func bestMatch(
        in songs: [MusicKit.Song],
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
            else if !t.isEmpty {
                // partial token overlap
                let tParts = t.split(separator: " ")
                if tParts.contains(where: { st.contains($0) }) { score += 15 }
            }
            if !a.isEmpty {
                if sa == a { score += 40 }
                else if sa.contains(a) || a.contains(sa) { score += 20 }
                for part in a.split(whereSeparator: { $0 == "/" || $0 == "," || $0 == "&" || $0 == "、" }) {
                    let p = normalize(String(part))
                    if !p.isEmpty, sa.contains(p) { score += 10 }
                }
            }
            if song.playParameters != nil { score += 5 }
            scored.append((song, score))
        }
        scored.sort { $0.1 > $1.1 }
        // Prefer playable matches; fall back to top score.
        if let bestPlayable = scored.first(where: { $0.0.playParameters != nil && $0.1 >= 15 }) {
            return bestPlayable.0
        }
        if let best = scored.first, best.1 >= 15 {
            return best.0
        }
        return songs.first(where: { $0.playParameters != nil }) ?? songs.first
    }

    private func normalize(_ s: String) -> String {
        scrubSearchToken(s)
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var lastPlaying = true
            var stuckZeroTicks = 0
            while !Task.isCancelled {
                guard let self, self.isActive else { break }
                let status = self.player.state.playbackStatus
                let playing = status == .playing
                let position = self.player.playbackTime
                let duration = self.activeDuration
                self.onPlaybackState?(playing, position, duration)

                // If "playing" but position stuck at 0 for long, kick play again once.
                if playing, position < 0.05 {
                    stuckZeroTicks += 1
                    if stuckZeroTicks == 8 {
                        try? await self.player.play()
                    }
                } else {
                    stuckZeroTicks = 0
                }

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
