import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PlayerStore {
    private(set) var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var progress: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var seekRevision = 0
    private(set) var isLoading = false
    private(set) var playbackIssue: PlaybackIssue?
    private(set) var volume: Double = 1
    private(set) var repeatMode: RepeatMode = .off
    /// True when current audio is ApplicationMusicPlayer (Apple Music).
    private(set) var isUsingAppleMusic = false
    /// Matched Apple Music track label for UI.
    private(set) var appleMusicMatchLabel: String?
    /// Human-readable active source layer (失败链 / 状态条).
    private(set) var sourceLayer: PlaybackSourceLayer = .none
    /// Short status for UI (e.g. 网易云试听兜底 / Apple Music 完整曲).
    private(set) var sourceStatusMessage: String?
    /// Transient toast (切源提示).
    private(set) var toastMessage: String?
    /// Match picker sheet.
    var showsAppleMusicMatchPicker = false
    private(set) var appleMusicCandidates: [AppleMusicCandidate] = []
    private(set) var isLoadingAppleMusicCandidates = false
    private(set) var appleMusicCandidateError: String?

    private var playbackQueue = PlaybackQueue()
    private let rescueStats = AppleMusicRescueStats.shared

    var queue: [Song] { playbackQueue.songs }
    var currentIndex: Int { playbackQueue.currentIndex }
    var isShuffled: Bool { playbackQueue.isShuffled }
    var canPlayNext: Bool {
        queue.count > 1 && playbackQueue.canMove(by: 1, wraps: repeatMode == .all)
    }

    @ObservationIgnored
    private let api: NeteaseAPI

    @ObservationIgnored
    private let settings: MeloXSettings

    @ObservationIgnored
    private let downloads: DownloadStore

    @ObservationIgnored
    private let engine: AudioPlaybackEngine

    @ObservationIgnored
    private let nowPlayingSession: NowPlayingSession

    @ObservationIgnored
    private let persistence: PlaybackPersistence

    @ObservationIgnored
    private let historyRecorder: PlaybackHistoryRecorder

    @ObservationIgnored
    private var loadGeneration = 0

    @ObservationIgnored
    private var isResolvingSource = false

    @ObservationIgnored
    private var hasRestoredPlayback = false

    @ObservationIgnored
    private var shouldResumeAfterInterruption = false

    @ObservationIgnored
    private var lastPersistedSecond = -1

    @ObservationIgnored
    private var lastProgressUpdateDate = Date()

    @ObservationIgnored
    private var historySourceID: Int?

    @ObservationIgnored
    private var hasRecordedCurrentStart = false

    @ObservationIgnored
    private var isUsingDownloadedSource = false

    @ObservationIgnored
    private var currentLoadShouldAutoplay = false

    @ObservationIgnored
    private let appleMusic = AppleMusicBridge.shared

    init(
        api: NeteaseAPI,
        settings: MeloXSettings,
        downloads: DownloadStore,
        persistence: PlaybackPersistence? = nil,
        onPlaybackRecorded: @escaping (Song) -> Void = { _ in }
    ) {
        self.api = api
        self.settings = settings
        self.downloads = downloads
        self.persistence = persistence ?? PlaybackPersistence()
        historyRecorder = PlaybackHistoryRecorder(
            api: api,
            settings: settings,
            onRecorded: onPlaybackRecorded
        )
        engine = AudioPlaybackEngine(
            equalizerConfiguration: settings.equalizer.configuration
        )
        nowPlayingSession = NowPlayingSession(player: engine.nowPlayingPlayer)
        bindEngine()
        bindRemoteCommands()
        bindAppleMusic()
        applyVolumeControlMode()
    }

    func restore() async {
        guard !hasRestoredPlayback else { return }
        hasRestoredPlayback = true
        guard let snapshot = persistence.load(), !snapshot.queue.isEmpty else { return }

        playbackQueue.restore(
            songs: snapshot.queue,
            currentIndex: snapshot.currentIndex,
            isShuffled: snapshot.isShuffled,
            shuffledOrder: snapshot.shuffledOrder
        )
        currentSong = playbackQueue.currentSong
        progress = max(snapshot.progress, 0)
        lastProgressUpdateDate = Date()
        duration = TimeInterval(currentSong?.durationMS ?? 0) / 1_000
        repeatMode = RepeatMode(rawValue: snapshot.repeatMode) ?? .off
        volume = min(max(snapshot.volume, 0), 1)
        historySourceID = snapshot.historySourceID
        applyVolumeControlMode()

        await loadCurrentSong(
            autoplay: false,
            startAt: progress
        )
    }

    func play(
        _ song: Song,
        in songs: [Song]? = nil,
        sourceID: Int? = nil
    ) async {
        recordCurrentPlayback()
        if let songs, !songs.isEmpty {
            let index = songs.firstIndex(where: { $0.id == song.id }) ?? 0
            playbackQueue.replace(with: songs, startingAt: index)
            historySourceID = sourceID
        } else if let existingIndex = queue.firstIndex(where: { $0.id == song.id }) {
            _ = playbackQueue.select(index: existingIndex)
        } else {
            playbackQueue.replace(with: [song], startingAt: 0)
            historySourceID = sourceID
        }
        hasRecordedCurrentStart = false
        await loadCurrentSong(autoplay: true)
    }

    func playAll(_ songs: [Song], sourceID: Int? = nil) async {
        guard !songs.isEmpty else { return }
        recordCurrentPlayback()
        playbackQueue.replace(with: songs, startingAt: 0)
        historySourceID = sourceID
        hasRecordedCurrentStart = false
        await loadCurrentSong(autoplay: true)
    }

    func togglePlayback() {
        guard currentSong != nil else { return }
        if isUsingAppleMusic {
            if isPlaying {
                appleMusic.pause()
                isPlaying = false
                persistSnapshot()
            } else {
                playbackIssue = nil
                Task { @MainActor [weak self] in
                    try? await self?.appleMusic.resume()
                }
            }
            return
        }
        if engine.hasCurrentItem {
            if isPlaying {
                engine.pause()
                persistSnapshot()
            } else {
                playbackIssue = nil
                engine.play()
            }
        } else {
            Task { @MainActor [weak self] in
                await self?.retry()
            }
        }
    }

    func retry() async {
        guard currentSong != nil else { return }
        stopAppleMusicIfNeeded()
        await loadCurrentSong(autoplay: true)
    }

    /// Switch current track to Apple Music catalog playback (MusicKit).
    /// - Parameters:
    ///   - reason: Why we switched (for toast / stats).
    ///   - recordRescue: Count toward weekly rescue stats.
    /// Last Apple Music failure (surfaced when auto-fallback fails).
    private(set) var lastAppleMusicError: Error?
    private(set) var lastNavidromeError: Error?
    /// Label when streaming from Navidrome match.
    private(set) var navidromeMatchLabel: String?

    @ObservationIgnored
    private let navidrome = NavidromeClient.shared

    @discardableResult
    func playViaAppleMusic(
        reason: AppleMusicSwitchReason = .manual,
        recordRescue: Bool = true,
        surfaceError: Bool = true
    ) async -> Bool {
        guard let song = currentSong else { return false }
        isLoading = true
        if reason == .manual {
            playbackIssue = nil
        }
        // Tear down Netease AVPlayer path before starting AM (避免双源叠音).
        engine.unload()
        isUsingDownloadedSource = false
        do {
            let matched = try await appleMusic.playMatching(
                title: song.name,
                artist: song.artistText,
                neteaseSongID: song.id
            )
            isUsingAppleMusic = true
            lastAppleMusicError = nil
            appleMusicMatchLabel = "\(matched.title) · \(matched.artistName)"
            sourceLayer = .appleMusic
            sourceStatusMessage = reason.statusLine(match: appleMusicMatchLabel)
            isLoading = false
            isPlaying = true
            duration = matched.duration ?? TimeInterval(song.durationMS) / 1_000
            progress = 0
            lastProgressUpdateDate = Date()
            nowPlayingSession.setSong(
                song,
                duration: duration,
                queueIndex: currentIndex,
                queueCount: queue.count
            )
            updateNowPlayingState()
            persistSnapshot()
            recordCurrentPlaybackStartIfNeeded()
            if recordRescue, reason.countsAsRescue {
                rescueStats.record(neteaseSongID: song.id, reason: reason.rawValue)
            }
            showToast(reason.toastMessage)
            return true
        } catch {
            // MusicKit 无 developer token 时无法应用内真播放：用 iTunes 搜索并打开系统 Apple Music。
            if AppleMusicBridge.isDeveloperTokenFailure(error)
                || (error as? AppleMusicBridge.BridgeError)?.isDeveloperTokenIssue == true {
                if await openSystemAppleMusic(for: song, reason: reason, recordRescue: recordRescue) {
                    return true
                }
            }
            isUsingAppleMusic = false
            appleMusicMatchLabel = nil
            lastAppleMusicError = error
            isLoading = false
            isPlaying = false
            sourceStatusMessage = "Apple Music 失败：\(error.localizedDescription)"
            // Always surface real AM error (manual or auto) so VIP 换源不会「没反应」。
            if surfaceError {
                playbackIssue = PlaybackIssue(song: song, error: error)
            }
            updateNowPlayingState()
            persistSnapshot()
            return false
        }
    }

    /// When MusicKit developer token is unavailable, open the matched track in the system Music app.
    @discardableResult
    private func openSystemAppleMusic(
        for song: Song,
        reason: AppleMusicSwitchReason,
        recordRescue: Bool
    ) async -> Bool {
        do {
            guard let hit = try await ITunesMusicLookup.bestMatch(
                title: song.name,
                artist: song.artistText
            ) else {
                lastAppleMusicError = AppleMusicBridge.BridgeError.noMatch(
                    title: song.name,
                    artist: song.artistText
                )
                return false
            }

            // Prefer music:// deep link; fall back to https track view URL.
            let candidates = [hit.appleMusicOpenURL, hit.trackViewURL].compactMap { $0 }
            var opened = false
            for url in candidates {
                opened = await UIApplication.shared.open(url)
                if opened { break }
            }
            guard opened else {
                lastAppleMusicError = AppleMusicBridge.BridgeError.playFailed(
                    "已找到曲目但无法打开系统 Apple Music（\(hit.trackName)）。"
                )
                return false
            }

            isUsingAppleMusic = false
            lastAppleMusicError = nil
            appleMusicMatchLabel = "\(hit.trackName) · \(hit.artistName)"
            sourceLayer = .appleMusicExternal
            sourceStatusMessage = "已在系统 Apple Music 打开（无 MusicKit 令牌，无法应用内真播放）"
            isLoading = false
            isPlaying = false
            if let ms = hit.trackTimeMillis, ms > 0 {
                duration = TimeInterval(ms) / 1_000
            }
            updateNowPlayingState()
            persistSnapshot()
            if recordRescue, reason.countsAsRescue {
                rescueStats.record(neteaseSongID: song.id, reason: "external-\(reason.rawValue)")
            }
            showToast("已跳转 Apple Music：《\(hit.trackName)》")
            playbackIssue = nil
            return true
        } catch {
            lastAppleMusicError = error
            return false
        }
    }

    /// Force-play a song via Apple Music without first loading Netease (avoids trial race).
    func playViaAppleMusic(
        song: Song,
        in songs: [Song]? = nil,
        sourceID: Int? = nil
    ) async {
        await prepareQueue(song: song, in: songs, sourceID: sourceID)
        _ = await playViaAppleMusic(reason: .manual, recordRescue: false, surfaceError: true)
    }

    /// Match current (or given) track in Navidrome and stream full file via AVPlayer.
    @discardableResult
    func playViaNavidrome(
        song overrideSong: Song? = nil,
        surfaceError: Bool = true
    ) async -> Bool {
        let song = overrideSong ?? currentSong
        guard let song else { return false }
        if overrideSong != nil, currentSong?.id != song.id {
            await prepareQueue(song: song, in: nil, sourceID: nil)
        }
        guard settings.navidromeIsConfigured else {
            let err = NavidromeClient.ClientError.notConfigured
            lastNavidromeError = err
            if surfaceError {
                playbackIssue = PlaybackIssue(song: song, error: err)
            }
            return false
        }

        isLoading = true
        if surfaceError { playbackIssue = nil }
        stopAppleMusicIfNeeded()
        engine.unload()
        isUsingDownloadedSource = false
        isUsingAppleMusic = false

        do {
            let (source, hit) = try await navidrome.playbackSource(
                title: song.name,
                artist: song.artistText,
                settings: settings
            )
            guard currentSong?.id == song.id else { return false }
            navidromeMatchLabel = "\(hit.title) · \(hit.artist)"
            lastNavidromeError = nil
            sourceLayer = .navidrome
            sourceStatusMessage = "Navidrome · \(hit.title) · \(hit.artist)"
            if hit.duration > 0 {
                duration = TimeInterval(hit.duration)
            }
            progress = 0
            lastProgressUpdateDate = Date()
            isResolvingSource = false
            await engine.load(source, startAt: 0, autoplay: true)
            isLoading = false
            isPlaying = true
            nowPlayingSession.setSong(
                song,
                duration: duration,
                queueIndex: currentIndex,
                queueCount: queue.count
            )
            updateNowPlayingState()
            persistSnapshot()
            recordCurrentPlaybackStartIfNeeded()
            showToast("Navidrome 完整播放：\(hit.title)")
            return true
        } catch {
            lastNavidromeError = error
            navidromeMatchLabel = nil
            isLoading = false
            isPlaying = false
            sourceStatusMessage = "Navidrome 失败：\(error.localizedDescription)"
            if surfaceError {
                playbackIssue = PlaybackIssue(song: song, error: error)
            }
            updateNowPlayingState()
            persistSnapshot()
            return false
        }
    }

    func playViaNavidrome(
        song: Song,
        in songs: [Song]? = nil,
        sourceID: Int? = nil
    ) async {
        await prepareQueue(song: song, in: songs, sourceID: sourceID)
        _ = await playViaNavidrome(song: song, surfaceError: true)
    }

    private func prepareQueue(
        song: Song,
        in songs: [Song]?,
        sourceID: Int?
    ) async {
        recordCurrentPlayback()
        if let songs, !songs.isEmpty {
            let index = songs.firstIndex(where: { $0.id == song.id }) ?? 0
            playbackQueue.replace(with: songs, startingAt: index)
            historySourceID = sourceID
        } else if let existingIndex = queue.firstIndex(where: { $0.id == song.id }) {
            _ = playbackQueue.select(index: existingIndex)
        } else {
            playbackQueue.replace(with: [song], startingAt: 0)
            historySourceID = sourceID
        }
        hasRecordedCurrentStart = false
        currentSong = song
        duration = TimeInterval(song.durationMS) / 1_000
        progress = 0
        stopAppleMusicIfNeeded()
        engine.unload()
        nowPlayingSession.setSong(
            song,
            duration: duration,
            queueIndex: currentIndex,
            queueCount: queue.count
        )
    }

    /// Shared fallback: Navidrome (if enabled) then Apple Music.
    private func tryAlternateFullSources(
        for song: Song,
        generation: Int,
        preferNavidrome: Bool
    ) async -> Bool {
        guard generation == loadGeneration, currentSong?.id == song.id else { return false }

        let tryNav = settings.navidromeEnabled && settings.navidromeIsConfigured
        let tryAM = settings.audioSourcePolicy.allowsAutomaticAppleMusic

        if preferNavidrome {
            if tryNav {
                let ok = await playViaNavidrome(surfaceError: false)
                if ok { return true }
            }
            if tryAM {
                let ok = await playViaAppleMusic(
                    reason: .trialPreview,
                    recordRescue: true,
                    surfaceError: false
                )
                if ok { return true }
            }
        } else {
            if tryAM {
                let ok = await playViaAppleMusic(
                    reason: .noSource,
                    recordRescue: true,
                    surfaceError: false
                )
                if ok { return true }
            }
            if tryNav {
                let ok = await playViaNavidrome(surfaceError: false)
                if ok { return true }
            }
        }
        return false
    }

    func presentAppleMusicMatchPicker() async {
        guard let song = currentSong else { return }
        showsAppleMusicMatchPicker = true
        isLoadingAppleMusicCandidates = true
        appleMusicCandidateError = nil
        appleMusicCandidates = []
        do {
            appleMusicCandidates = try await appleMusic.searchCandidates(
                title: song.name,
                artist: song.artistText
            )
            if appleMusicCandidates.isEmpty {
                appleMusicCandidateError = "未找到候选曲目。"
            }
        } catch {
            appleMusicCandidateError = error.localizedDescription
        }
        isLoadingAppleMusicCandidates = false
    }

    /// Play a pure Apple Music catalog hit (Search tab), using a lightweight Song shell for UI.
    func playAppleMusicCatalogCandidate(_ candidate: AppleMusicCandidate) async {
        let shell = Song(
            id: stableSyntheticID(for: candidate.id),
            name: candidate.title,
            artists: [Artist(id: 0, name: candidate.artistName)],
            album: candidate.albumTitle.map { Album(id: 0, name: $0) },
            durationMS: Int((candidate.duration ?? 0) * 1_000)
        )
        recordCurrentPlayback()
        playbackQueue.replace(with: [shell], startingAt: 0)
        historySourceID = nil
        hasRecordedCurrentStart = false
        currentSong = shell
        duration = candidate.duration ?? 0
        progress = 0
        await playAppleMusicCandidate(candidate, bindNeteaseCache: false)
    }

    func playAppleMusicCandidate(
        _ candidate: AppleMusicCandidate,
        bindNeteaseCache: Bool = true
    ) async {
        guard let song = currentSong else { return }
        isLoading = true
        playbackIssue = nil
        engine.unload()
        isUsingDownloadedSource = false
        do {
            let matched = try await appleMusic.playMusicItemID(
                candidate.id,
                neteaseSongID: bindNeteaseCache ? song.id : nil
            )
            isUsingAppleMusic = true
            appleMusicMatchLabel = "\(matched.title) · \(matched.artistName)"
            sourceLayer = .appleMusic
            sourceStatusMessage = "Apple Music · 已指定匹配"
            isLoading = false
            isPlaying = true
            duration = matched.duration ?? TimeInterval(song.durationMS) / 1_000
            progress = 0
            lastProgressUpdateDate = Date()
            nowPlayingSession.setSong(
                song,
                duration: duration,
                queueIndex: currentIndex,
                queueCount: queue.count
            )
            updateNowPlayingState()
            persistSnapshot()
            recordCurrentPlaybackStartIfNeeded()
            showToast("已切换匹配：\(matched.title)")
        } catch {
            isUsingAppleMusic = false
            appleMusicMatchLabel = nil
            isLoading = false
            isPlaying = false
            playbackIssue = PlaybackIssue(song: song, error: error)
            updateNowPlayingState()
            persistSnapshot()
        }
    }

    private func stableSyntheticID(for musicItemID: String) -> Int {
        // Positive stable id for Identifiable queues; avoid clashing with real Netease ids when possible.
        var hash = 5381
        for byte in musicItemID.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash % 900_000_000) + 100_000_000
    }

    func dismissPlaybackIssue() {
        playbackIssue = nil
    }

    func dismissToast() {
        toastMessage = nil
    }

    var sourceLayerTitle: String {
        sourceLayer.title
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    func reloadCurrentSongForQualityChange() async {
        guard currentSong != nil else { return }
        let shouldAutoplay = isPlaying
        let resumePosition = estimatedProgress()
        await loadCurrentSong(
            autoplay: shouldAutoplay,
            startAt: resumePosition
        )
    }

    func next() async {
        await moveToNext(recordingCurrentPlayback: true)
    }

    private func moveToNext(recordingCurrentPlayback: Bool) async {
        guard !queue.isEmpty else { return }
        if recordingCurrentPlayback {
            recordCurrentPlayback()
        }
        guard playbackQueue.move(by: 1, wraps: repeatMode == .all) else {
            stopAtQueueEnd()
            return
        }
        hasRecordedCurrentStart = false
        await loadCurrentSong(autoplay: true)
    }

    func previous() async {
        guard !queue.isEmpty else { return }
        if settings.previousRestartsCurrentSong, progress > 5 {
            seek(to: 0)
            return
        }
        guard playbackQueue.canMove(by: -1, wraps: repeatMode == .all) else {
            seek(to: 0)
            return
        }
        recordCurrentPlayback()
        guard playbackQueue.move(by: -1, wraps: repeatMode == .all) else { return }
        hasRecordedCurrentStart = false
        await loadCurrentSong(autoplay: true)
    }

    func playFromQueue(at index: Int) async {
        guard queue.indices.contains(index) else { return }
        recordCurrentPlayback()
        guard playbackQueue.select(index: index) else { return }
        hasRecordedCurrentStart = false
        await loadCurrentSong(autoplay: true)
    }

    func seek(to seconds: TimeInterval) {
        let maximum = duration > 0 ? duration : TimeInterval(currentSong?.durationMS ?? 0) / 1_000
        let clamped = max(0, min(seconds, maximum))
        if isUsingAppleMusic {
            appleMusic.seek(to: clamped)
        } else {
            engine.seek(to: clamped)
        }
        progress = clamped
        seekRevision += 1
        lastProgressUpdateDate = Date()
        updateNowPlayingState()
        persistSnapshot()
    }

    func estimatedProgress(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return progress }
        let elapsed = max(date.timeIntervalSince(lastProgressUpdateDate), 0)
        let maximum = duration > 0 ? duration : TimeInterval(currentSong?.durationMS ?? 0) / 1_000
        let estimated = progress + elapsed
        return maximum > 0 ? min(estimated, maximum) : estimated
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        applyVolumeControlMode()
        persistSnapshot()
    }

    func applyVolumeControlMode() {
        let effectiveVolume = settings.playerVolumeControlMode == .independent
            ? volume
            : 1
        engine.setVolume(effectiveVolume)
    }

    func applyEqualizerSettings() {
        engine.setEqualizerConfiguration(settings.equalizer.configuration)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        persistSnapshot()
    }

    func toggleShuffle() {
        playbackQueue.toggleShuffle()
        persistSnapshot()
    }

    private func loadCurrentSong(
        autoplay: Bool,
        startAt: TimeInterval = 0
    ) async {
        guard let song = playbackQueue.currentSong else { return }
        loadGeneration += 1
        let generation = loadGeneration
        currentSong = song
        progress = max(0, startAt)
        lastProgressUpdateDate = Date()
        duration = TimeInterval(song.durationMS) / 1_000
        isResolvingSource = true
        isLoading = true
        isPlaying = false
        isUsingDownloadedSource = false
        stopAppleMusicIfNeeded()
        currentLoadShouldAutoplay = autoplay
        playbackIssue = nil
        engine.unload()
        nowPlayingSession.setSong(
            song,
            duration: duration,
            queueIndex: currentIndex,
            queueCount: queue.count
        )
        updateNowPlayingState()
        persistSnapshot()

        let policy = settings.audioSourcePolicy

        // 优先 AM：起播前直接 MusicKit，失败再走网易云（本地下载仍优先）。
        if policy.prefersAppleMusicFirst,
           autoplay,
           downloads.localPlaybackSource(songID: song.id) == nil {
            isResolvingSource = false
            let ok = await playViaAppleMusic(reason: .preferPolicy, recordRescue: true)
            if ok, generation == loadGeneration { return }
            guard generation == loadGeneration, currentSong?.id == song.id else { return }
            // fall through to Netease chain
        }

        do {
            let source: PlaybackSource
            if let downloadedSource = downloads.localPlaybackSource(songID: song.id) {
                source = downloadedSource
                isUsingDownloadedSource = true
            } else {
                source = try await api.playbackSource(id: song.id)
            }
            guard generation == loadGeneration, currentSong?.id == song.id else { return }

            // 起播前识别试听：不加载短流；Navidrome → Apple Music → 试听兜底。
            if source.isTrialPreview, autoplay {
                let wantAlt = (settings.navidromeEnabled && settings.navidromeIsConfigured)
                    || policy.allowsAutomaticAppleMusic
                if wantAlt {
                    isResolvingSource = false
                    let ok = await tryAlternateFullSources(
                        for: song,
                        generation: generation,
                        preferNavidrome: settings.navidromeBeforeAppleMusic
                    )
                    if ok { return }
                    sourceLayer = .neteaseTrial
                    sourceStatusMessage = "失败链：完整源均失败 → 网易云试听兜底"
                    showToast("完整音源不可用，正在播放网易云试听")
                    playbackIssue = PlaybackIssue(
                        song: song,
                        error: APIError.trialPreviewOnly,
                        appleMusicError: lastAppleMusicError ?? lastNavidromeError
                    )
                }
            } else if source.isTrialPreview {
                sourceLayer = .neteaseTrial
                sourceStatusMessage = "网易云试听片段（策略：仅网易云）"
            } else if isUsingDownloadedSource {
                sourceLayer = .localDownload
                sourceStatusMessage = "本地下载"
            } else {
                sourceLayer = .neteaseFull
                sourceStatusMessage = "网易云完整音源"
            }

            isResolvingSource = false
            await engine.load(
                source,
                startAt: startAt,
                autoplay: autoplay
            )
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, currentSong?.id == song.id else { return }
            isResolvingSource = false
            let wantAlternate =
                (settings.navidromeEnabled && settings.navidromeIsConfigured)
                || policy.allowsAutomaticAppleMusic
            if wantAlternate, autoplay {
                let ok = await tryAlternateFullSources(
                    for: song,
                    generation: generation,
                    preferNavidrome: settings.navidromeBeforeAppleMusic
                )
                if ok { return }
                sourceStatusMessage = "失败链：网易云失败 → Navidrome/Apple Music 也失败"
                playbackIssue = PlaybackIssue(
                    song: song,
                    error: error,
                    appleMusicError: lastAppleMusicError ?? lastNavidromeError
                )
                isLoading = false
                isPlaying = false
                sourceLayer = .none
                updateNowPlayingState()
                persistSnapshot()
                return
            }
            isLoading = false
            isPlaying = false
            sourceLayer = .none
            playbackIssue = PlaybackIssue(
                song: song,
                error: error,
                appleMusicError: lastAppleMusicError
            )
            updateNowPlayingState()
            persistSnapshot()
        }
    }

    /// 音源加载后若实际时长远短于曲目元数据（外链/漏标试听），再切 Apple Music。
    private func maybeFallbackIfNeteasePreviewClip(
        actualDuration: TimeInterval,
        generation: Int
    ) {
        guard !isUsingAppleMusic, !isUsingDownloadedSource else { return }
        guard settings.audioSourcePolicy.allowsAutomaticAppleMusic else { return }
        guard generation == loadGeneration else { return }
        guard let song = currentSong, song.durationMS > 0 else { return }
        guard actualDuration > 0 else { return }

        let catalog = TimeInterval(song.durationMS) / 1_000
        guard catalog >= 90 else { return }
        let looksLikeTrial =
            actualDuration <= 45
            || (actualDuration <= 90 && actualDuration < catalog * 0.4)
            || actualDuration < catalog * 0.25
        guard looksLikeTrial else { return }

        // 起播后发现试听：立刻卸掉短流再切完整曲，避免听一半硬切错位。
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.loadGeneration == generation, self.currentSong?.id == song.id else { return }
            guard !self.isUsingAppleMusic else { return }
            self.engine.unload()
            self.showToast("检测到试听片段，正在切换完整版…")
            let ok = await self.tryAlternateFullSources(
                for: song,
                generation: generation,
                preferNavidrome: self.settings.navidromeBeforeAppleMusic
            )
            if !ok {
                self.playbackIssue = PlaybackIssue(
                    song: song,
                    error: APIError.trialPreviewOnly,
                    appleMusicError: self.lastAppleMusicError ?? self.lastNavidromeError
                )
                self.sourceLayer = .neteaseTrial
                self.sourceStatusMessage = "失败链：时长探测试听 → 完整源失败"
            }
        }
    }

    private func stopAppleMusicIfNeeded() {
        if isUsingAppleMusic || appleMusic.isActive {
            appleMusic.stop()
        }
        isUsingAppleMusic = false
        appleMusicMatchLabel = nil
        navidromeMatchLabel = nil
        if sourceLayer == .appleMusic || sourceLayer == .navidrome {
            sourceLayer = .none
            sourceStatusMessage = nil
        }
    }

    private func bindAppleMusic() {
        appleMusic.onPlaybackState = { [weak self] playing, position, duration in
            guard let self, self.isUsingAppleMusic else { return }
            self.isPlaying = playing
            self.isLoading = false
            self.progress = position
            if duration > 0 {
                self.duration = duration
            }
            self.lastProgressUpdateDate = Date()
            self.updateNowPlayingState()
        }
        appleMusic.onEnded = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.handlePlaybackEnded()
            }
        }
    }

    private func handlePlaybackEnded() async {
        recordCurrentPlayback(completed: true)
        if repeatMode == .one {
            hasRecordedCurrentStart = false
            seek(to: 0)
            if isUsingAppleMusic {
                try? await appleMusic.resume()
            } else {
                engine.play()
            }
            return
        }
        await moveToNext(recordingCurrentPlayback: false)
    }

    private func handleEngineFailure(_ error: Error) async {
        if let playbackError = error as? AudioPlaybackError,
           case .itemFailed = playbackError,
           isUsingDownloadedSource,
           let song = currentSong {
            let resumePosition = progress
            let shouldAutoplay = currentLoadShouldAutoplay
            isUsingDownloadedSource = false
            downloads.discardInvalidDownload(songID: song.id)
            await loadCurrentSong(
                autoplay: shouldAutoplay,
                startAt: resumePosition
            )
            return
        }

        if let song = currentSong {
            playbackIssue = PlaybackIssue(song: song, error: error)
        }
        isLoading = false
        isPlaying = false
        updateNowPlayingState()

        if let playbackError = error as? AudioPlaybackError,
           case .itemFailed = playbackError {
            engine.unload()
        }
        persistSnapshot()
    }

    private func stopAtQueueEnd() {
        if isUsingAppleMusic {
            appleMusic.pause()
            appleMusic.seek(to: 0)
        } else {
            engine.pause()
            engine.seek(to: 0)
        }
        progress = 0
        lastProgressUpdateDate = Date()
        isPlaying = false
        isLoading = false
        updateNowPlayingState()
        persistSnapshot()
    }

    private func bindEngine() {
        engine.onStateChanged = { [weak self] state in
            guard let self else { return }
            switch state {
            case .idle:
                self.isPlaying = false
                if !self.isResolvingSource {
                    self.isLoading = false
                }
            case .loading:
                self.isPlaying = false
                self.isLoading = true
            case .paused:
                self.isPlaying = false
                self.isLoading = false
            case .playing:
                self.isPlaying = true
                self.isLoading = false
                self.playbackIssue = nil
                self.recordCurrentPlaybackStartIfNeeded()
            }
            self.lastProgressUpdateDate = Date()
            self.updateNowPlayingState()
        }
        engine.onProgressChanged = { [weak self] value in
            guard let self else { return }
            self.progress = value
            self.lastProgressUpdateDate = Date()
            let second = Int(value)
            if second != self.lastPersistedSecond {
                self.lastPersistedSecond = second
                self.persistSnapshot()
            }
        }
        engine.onDurationChanged = { [weak self] value in
            guard let self else { return }
            self.duration = value
            self.updateNowPlayingState()
            // 网易云偶发不带 freeTrialInfo 的外链试听：用实际时长二次判定。
            self.maybeFallbackIfNeteasePreviewClip(
                actualDuration: value,
                generation: self.loadGeneration
            )
        }
        engine.onPlaybackEnded = { [weak self] in
            Task { @MainActor in
                await self?.handlePlaybackEnded()
            }
        }
        engine.onFailure = { [weak self] error in
            Task { @MainActor in
                await self?.handleEngineFailure(error)
            }
        }
        engine.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.shouldResumeAfterInterruption = self.isPlaying
            if self.isUsingAppleMusic {
                self.appleMusic.pause()
            } else {
                self.engine.pause()
            }
        }
        engine.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            if shouldResume, self.shouldResumeAfterInterruption {
                if self.isUsingAppleMusic {
                    Task { @MainActor in try? await self.appleMusic.resume() }
                } else {
                    self.engine.play()
                }
            }
            self.shouldResumeAfterInterruption = false
        }
        engine.onOutputDeviceDisconnected = { [weak self] in
            self?.shouldResumeAfterInterruption = false
        }
    }

    private func bindRemoteCommands() {
        nowPlayingSession.onPlay = { [weak self] in
            guard let self else { return }
            if self.isUsingAppleMusic {
                Task { @MainActor in try? await self.appleMusic.resume() }
            } else if self.engine.hasCurrentItem {
                self.engine.play()
            } else {
                Task { @MainActor in await self.retry() }
            }
        }
        nowPlayingSession.onPause = { [weak self] in
            guard let self else { return }
            if self.isUsingAppleMusic {
                self.appleMusic.pause()
            } else {
                self.engine.pause()
            }
        }
        nowPlayingSession.onNext = { [weak self] in
            Task { @MainActor in await self?.next() }
        }
        nowPlayingSession.onPrevious = { [weak self] in
            Task { @MainActor in await self?.previous() }
        }
        nowPlayingSession.onSeek = { [weak self] position in
            self?.seek(to: position)
        }
    }

    private func updateNowPlayingState() {
        nowPlayingSession.updatePlayback(
            position: progress,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func recordCurrentPlayback(completed: Bool = false) {
        guard hasRecordedCurrentStart, let currentSong else { return }
        historyRecorder.recordPlaybackDuration(
            song: currentSong,
            sourceID: historySourceID,
            playbackTime: estimatedProgress(),
            completed: completed
        )
    }

    private func recordCurrentPlaybackStartIfNeeded() {
        guard !hasRecordedCurrentStart, let currentSong else { return }
        hasRecordedCurrentStart = true
        historyRecorder.recordRecentPlayback(
            song: currentSong,
            sourceID: historySourceID
        )
        downloads.recordPlayback(currentSong)
    }

    private func persistSnapshot() {
        guard !queue.isEmpty else {
            persistence.clear()
            return
        }
        persistence.save(
            PlaybackSnapshot(
                queue: queue,
                currentIndex: currentIndex,
                progress: progress,
                repeatMode: repeatMode.rawValue,
                isShuffled: isShuffled,
                shuffledOrder: playbackQueue.persistedShuffleOrder,
                volume: volume,
                historySourceID: historySourceID
            )
        )
    }
}
