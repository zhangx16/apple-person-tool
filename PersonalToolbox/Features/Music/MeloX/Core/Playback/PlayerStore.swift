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
    /// True when current audio is ApplicationMusicPlayer (Apple Music).
    private(set) var isUsingAppleMusic = false
    /// Matched Apple Music track label for UI.
    private(set) var appleMusicMatchLabel: String?

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
    func playViaAppleMusic() async {
        guard let song = currentSong else { return }
        isLoading = true
        playbackIssue = nil
        // Tear down Netease AVPlayer path.
        engine.unload()
        isUsingDownloadedSource = false
        do {
            let matched = try await appleMusic.playMatching(
                title: song.name,
                artist: song.artistText
            )
            isUsingAppleMusic = true
            appleMusicMatchLabel = "\(matched.title) · \(matched.artistName)"
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

    func dismissPlaybackIssue() {
        playbackIssue = nil
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

        do {
            let source: PlaybackSource
            if let downloadedSource = downloads.localPlaybackSource(songID: song.id) {
                source = downloadedSource
                isUsingDownloadedSource = true
            } else {
                source = try await api.playbackSource(id: song.id)
            }
            guard generation == loadGeneration, currentSong?.id == song.id else { return }
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
            // Auto-fallback to Apple Music when Netease has no playable URL / failed.
            let shouldFallback: Bool
            if let apiError = error as? APIError, case .noPlayableSource = apiError {
                shouldFallback = true
            } else if error is AudioPlaybackError {
                shouldFallback = true
            } else {
                shouldFallback = settings.appleMusicAutoFallback
            }
            if shouldFallback, settings.appleMusicAutoFallback, autoplay {
                await playViaAppleMusic()
                if isUsingAppleMusic { return }
            }
            isLoading = false
            isPlaying = false
            playbackIssue = PlaybackIssue(song: song, error: error)
            updateNowPlayingState()
            persistSnapshot()
        }
    }

    private func stopAppleMusicIfNeeded() {
        if isUsingAppleMusic || appleMusic.isActive {
            appleMusic.stop()
        }
        isUsingAppleMusic = false
        appleMusicMatchLabel = nil
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
