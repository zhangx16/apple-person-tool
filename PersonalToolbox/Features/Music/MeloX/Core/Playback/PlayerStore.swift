import Foundation
import Observation

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
    /// Human-readable active source layer (失败链 / 状态条).
    private(set) var sourceLayer: PlaybackSourceLayer = .none
    /// Short status for UI (e.g. 网易云 / Navidrome).
    private(set) var sourceStatusMessage: String?
    /// Transient toast (切源提示).
    private(set) var toastMessage: String?
    private var playbackQueue = PlaybackQueue()
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
        clearAlternateSourceState()
        await loadCurrentSong(autoplay: true)
    }

    /// Last Navidrome match failure.
    private(set) var lastNavidromeError: Error?
    /// Label when streaming from Navidrome match.
    private(set) var navidromeMatchLabel: String?

    @ObservationIgnored
    private let navidrome = NavidromeClient.shared

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
        clearAlternateSourceState()
        engine.unload()
        isUsingDownloadedSource = false

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
        clearAlternateSourceState()
        engine.unload()
        nowPlayingSession.setSong(
            song,
            duration: duration,
            queueIndex: currentIndex,
            queueCount: queue.count
        )
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
        engine.seek(to: clamped)
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
        clearAlternateSourceState()
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

        do {
            let source: PlaybackSource
            if let downloadedSource = downloads.localPlaybackSource(songID: song.id) {
                source = downloadedSource
                isUsingDownloadedSource = true
            } else {
                source = try await api.playbackSource(id: song.id)
            }
            guard generation == loadGeneration, currentSong?.id == song.id else { return }

            // 试听/非完整：优先 Navidrome 完整流，失败再播网易云试听。
            if source.isTrialPreview, autoplay,
               settings.navidromeEnabled, settings.navidromeIsConfigured {
                isResolvingSource = false
                let ok = await playViaNavidrome(surfaceError: false)
                if ok { return }
                sourceLayer = .neteaseTrial
                sourceStatusMessage = "Navidrome 未命中 → 网易云试听兜底"
                showToast("Navidrome 无匹配，正在播放网易云试听")
                playbackIssue = PlaybackIssue(
                    song: song,
                    error: APIError.trialPreviewOnly,
                    alternateSourceError: lastNavidromeError
                )
            } else if source.isTrialPreview {
                sourceLayer = .neteaseTrial
                sourceStatusMessage = "网易云试听片段"
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
            if autoplay, settings.navidromeEnabled, settings.navidromeIsConfigured {
                let ok = await playViaNavidrome(surfaceError: false)
                if ok { return }
                sourceStatusMessage = "失败链：网易云失败 → Navidrome 也失败"
                playbackIssue = PlaybackIssue(
                    song: song,
                    error: error,
                    alternateSourceError: lastNavidromeError
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
            playbackIssue = PlaybackIssue(song: song, error: error)
            updateNowPlayingState()
            persistSnapshot()
        }
    }

    /// 音源加载后若实际时长远短于曲目元数据，再切 Navidrome。
    private func maybeFallbackIfNeteasePreviewClip(
        actualDuration: TimeInterval,
        generation: Int
    ) {
        guard !isUsingDownloadedSource else { return }
        guard settings.navidromeEnabled, settings.navidromeIsConfigured else { return }
        guard generation == loadGeneration else { return }
        guard sourceLayer != .navidrome else { return }
        guard let song = currentSong, song.durationMS > 0 else { return }
        guard actualDuration > 0 else { return }

        let catalog = TimeInterval(song.durationMS) / 1_000
        guard catalog >= 90 else { return }
        let looksLikeTrial =
            actualDuration <= 45
            || (actualDuration <= 90 && actualDuration < catalog * 0.4)
            || actualDuration < catalog * 0.25
        guard looksLikeTrial else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.loadGeneration == generation, self.currentSong?.id == song.id else { return }
            guard self.sourceLayer != .navidrome else { return }
            self.engine.unload()
            self.showToast("检测到试听片段，正在切换 Navidrome 完整版…")
            let ok = await self.playViaNavidrome(surfaceError: false)
            if !ok {
                self.playbackIssue = PlaybackIssue(
                    song: song,
                    error: APIError.trialPreviewOnly,
                    alternateSourceError: self.lastNavidromeError
                )
                self.sourceLayer = .neteaseTrial
                self.sourceStatusMessage = "失败链：试听探测 → Navidrome 失败"
            }
        }
    }

    private func clearAlternateSourceState() {
        navidromeMatchLabel = nil
        if sourceLayer == .navidrome {
            sourceLayer = .none
            sourceStatusMessage = nil
        }
    }

    private func handlePlaybackEnded() async {
        recordCurrentPlayback(completed: true)
        if repeatMode == .one {
            hasRecordedCurrentStart = false
            seek(to: 0)
            engine.play()
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
        engine.pause()
        engine.seek(to: 0)
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
            // Full-queue snapshot encode/write is comparatively expensive; only
            // do it every ~5s from the progress tick. Song/queue changes, pause,
            // seek, and backgrounding all persist immediately via their own
            // `persistSnapshot()` calls elsewhere, so resume points stay accurate.
            if second < self.lastPersistedSecond || second - self.lastPersistedSecond >= 5 {
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
            self.engine.pause()
        }
        engine.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            if shouldResume, self.shouldResumeAfterInterruption {
                self.engine.play()
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
            if self.engine.hasCurrentItem {
                self.engine.play()
            } else {
                Task { @MainActor in await self.retry() }
            }
        }
        nowPlayingSession.onPause = { [weak self] in
            guard let self else { return }
            self.engine.pause()
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
