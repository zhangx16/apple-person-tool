import SwiftUI
import AVKit
import AVFoundation
import UIKit

// MARK: - Audio session for local / downloaded media

/// Dedicated activator for the download player (not shared retain-count with Live/VLC).
/// Primary goal: beat the hardware silent switch and restore session after Live deactivates it.
enum DownloadPlaybackAudio {
    /// Activate a pure playback session. Tries several option sets until one succeeds.
    @discardableResult
    static func activate() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let attempts: [(mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)] = [
            // Simplest path — most reliable for speaker + silent-switch override.
            (.moviePlayback, []),
            (.default, []),
            // With external routes when available.
            (.moviePlayback, [.allowAirPlay, .allowBluetoothA2DP]),
            (.moviePlayback, [.allowAirPlay, .allowBluetoothA2DP, .mixWithOthers])
        ]
        for attempt in attempts {
            do {
                try session.setCategory(.playback, mode: attempt.mode, options: attempt.options)
                try session.setActive(true)
                return true
            } catch {
                continue
            }
        }
        // Last resort: category only, then active.
        try? session.setCategory(.playback)
        try? session.setActive(true)
        return session.category == .playback
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

// MARK: - Host VC (session + play in viewDidAppear)

/// Owns `AVPlayer` and only starts after the VC is on-screen so the audio session sticks.
final class DownloadPlayerHostController: AVPlayerViewController {
    var fileURL: URL?
    var autoplay: Bool = true
    private var didStart = false
    private var endObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        showsPlaybackControls = true
        videoGravity = .resizeAspect
        allowsPictureInPicturePlayback = true
        if #available(iOS 14.0, *) {
            canStartPictureInPictureAutomaticallyFromInline = true
        }
        if #available(iOS 16.0, *) {
            allowsVideoFrameAnalysis = true
        }
        // Early pin so first frames already route through .playback.
        _ = DownloadPlaybackAudio.activate()
        configurePlayerIfNeeded(forceReload: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startOrResumePlayback()
        startRouteObserver()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Pause when leaving, but leave session teardown to the representable/sheet.
        if isBeingDismissed || isMovingFromParent {
            player?.pause()
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }

    /// Call when the host becomes visible or the file URL changes.
    func startOrResumePlayback() {
        _ = DownloadPlaybackAudio.activate()
        configurePlayerIfNeeded(forceReload: false)
        ensureAudible()
        if autoplay {
            player?.play()
        }
    }

    func reload(url: URL, autoplay: Bool) {
        fileURL = url
        self.autoplay = autoplay
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        didStart = false
        startOrResumePlayback()
    }

    private func configurePlayerIfNeeded(forceReload: Bool) {
        guard let fileURL else { return }
        if !forceReload, let existing = player?.currentItem {
            // Already configured for this URL.
            if let asset = existing.asset as? AVURLAsset, asset.url == fileURL {
                return
            }
        }
        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)
        // Do not attach a silent audioMix.
        item.audioTimePitchAlgorithm = .spectral

        let p = AVPlayer(playerItem: item)
        p.isMuted = false
        p.volume = 1.0
        p.automaticallyWaitsToMinimizeStalling = true
        if #available(iOS 15.0, *) {
            p.audiovisualBackgroundPlaybackPolicy = .pauses
        }
        player = p
        didStart = true

        // If asset has selectable audio media options, force the first on.
        Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            await self.enableAudioTracks(on: item)
            self.ensureAudible()
            if self.autoplay, self.viewIfLoaded?.window != nil {
                self.player?.play()
            }
        }
    }

    private func ensureAudible() {
        player?.isMuted = false
        player?.volume = 1.0
    }

    func ensureAudiblePublic() {
        ensureAudible()
    }

    private func enableAudioTracks(on item: AVPlayerItem) async {
        // Prefer AVMediaSelectionGroup for alternative audio; for file assets this is often empty
        // and the default audio track is already enabled. Still force-enable any disabled tracks.
        let asset = item.asset
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            if tracks.isEmpty {
                // File has no audio — nothing the player can do.
                return
            }
            // Ensure composition-style assets aren't muted via empty audioMix.
            if item.audioMix != nil {
                item.audioMix = nil
            }
        } catch {
            // Best-effort.
        }

        if let group = try? await asset.loadMediaSelectionGroup(for: .audible),
           let option = group.options.first {
            item.select(option, in: group)
        }
    }

    private func startRouteObserver() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = DownloadPlaybackAudio.activate()
            self?.ensureAudible()
            if self?.autoplay == true {
                self?.player?.play()
            }
        }
    }
}

// MARK: - SwiftUI bridge

/// Full-screen system player for downloaded media.
struct SystemVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    var autoplay: Bool = true

    func makeUIViewController(context: Context) -> DownloadPlayerHostController {
        _ = DownloadPlaybackAudio.activate()
        let vc = DownloadPlayerHostController()
        vc.fileURL = url
        vc.autoplay = autoplay
        context.coordinator.host = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: DownloadPlayerHostController, context: Context) {
        if uiViewController.fileURL != url {
            uiViewController.reload(url: url, autoplay: autoplay)
        } else {
            // Orientation / cover re-layout can leave session inactive — re-pin.
            _ = DownloadPlaybackAudio.activate()
            uiViewController.ensureAudiblePublic()
        }
    }

    static func dismantleUIViewController(
        _ uiViewController: DownloadPlayerHostController,
        coordinator: Coordinator
    ) {
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
        coordinator.host = nil
        // Session released from VideoPlayerSheet.onDisappear to avoid race with orientation rebuild.
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var host: DownloadPlayerHostController?
    }
}

/// Full-screen landscape playback for completed downloads (iOS built-in player).
struct VideoPlayerSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            SystemVideoPlayer(url: url, autoplay: true)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.95), .black.opacity(0.35))
                    .padding(16)
            }
            .accessibilityLabel("关闭播放")
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            _ = DownloadPlaybackAudio.activate()
            OrientationHelper.lockLandscape()
        }
        .onDisappear {
            DownloadPlaybackAudio.deactivate()
            OrientationHelper.lockPortrait()
        }
    }
}

// MARK: - Helpers

enum DownloadMediaKind {
    case video
    case image
    case other

    static func detect(pathOrName: String) -> DownloadMediaKind {
        let ext = (pathOrName as NSString).pathExtension.lowercased()
        if ["mp4", "m4v", "mov", "mkv", "webm", "avi", "mpeg", "mpg"].contains(ext) {
            return .video
        }
        if ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif"].contains(ext) {
            return .image
        }
        return .other
    }

    var isPlayableVideo: Bool { self == .video }
}

/// Quick local probe: does this media file expose at least one audio track?
enum DownloadMediaAudioProbe {
    static func hasAudioTrack(at fileURL: URL) async -> Bool {
        let asset = AVURLAsset(url: fileURL)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } catch {
            return false
        }
    }
}
