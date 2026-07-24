import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer

/// Live playback audio session: pure output (no mic), A2DP for Bluetooth headsets.
/// Avoids playAndRecord / HFP call-path routing that causes headphone echo.
///
/// Retain-counted so tearing down the inline player while fullscreen mounts
/// does not deactivate the session out from under the new decoder.
enum LiveAudioSession {
    private static let lock = NSLock()
    private static var retainCount = 0

    static func activateForPlayback() {
        lock.lock()
        retainCount += 1
        lock.unlock()
        applyCategoryAndActivate()
    }

    /// Re-pin category after route changes without changing the retain count.
    static func reassertCategory() {
        applyCategoryAndActivate()
    }

    static func deactivateIfNeeded() {
        lock.lock()
        retainCount = max(0, retainCount - 1)
        let shouldDeactivate = retainCount == 0
        lock.unlock()
        guard shouldDeactivate else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func applyCategoryAndActivate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            // Best-effort; VLC may still open audio with the previous session.
        }
    }
}

// MARK: - System volume / brightness (fullscreen gestures)

/// System volume via hidden `MPVolumeView` slider (public API).
enum LiveSystemVolume {
    private static var volumeView: MPVolumeView?
    private static var slider: UISlider?

    static var current: Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    static func set(_ value: Float) {
        let clamped = max(0, min(1, value))
        ensureSlider()
        // Defer one runloop so the volume view attaches its slider if first use.
        if let slider {
            slider.value = clamped
        } else {
            DispatchQueue.main.async {
                ensureSlider()
                slider?.value = clamped
            }
        }
    }

    private static func ensureSlider() {
        if slider != nil { return }
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.showsRouteButton = false
        view.alpha = 0.01
        volumeView = view
        // Attach off-screen so the internal slider exists.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            window.addSubview(view)
        }
        slider = view.subviews.compactMap { $0 as? UISlider }.first
    }
}

enum LiveSystemBrightness {
    static var current: CGFloat {
        UIScreen.main.brightness
    }

    static func set(_ value: CGFloat) {
        UIScreen.main.brightness = max(0, min(1, value))
    }
}

#if canImport(MobileVLCKit)
import MobileVLCKit

/// In-app player for HTTP-FLV / HLS (LibVLC).
/// Mirrors SimpleLive's media_kit role: decode streams AVPlayer rejects.
struct LiveVLCPlayerView: UIViewRepresentable {
    let url: URL
    var headers: [String: String] = [:]
    var isPlaying: Bool = true
    /// Fired when LibVLC reports error / unexpected end (for reconnect).
    var onPlaybackFailed: (() -> Void)? = nil
    /// Fired when playback reaches playing state (reset retry counters).
    var onPlaying: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackFailed: onPlaybackFailed, onPlaying: onPlaying)
    }

    func makeUIView(context: Context) -> PlayerHostView {
        let host = PlayerHostView()
        host.backgroundColor = .black
        LiveAudioSession.activateForPlayback()
        let player = VLCMediaPlayer()
        player.drawable = host
        player.delegate = context.coordinator
        // Prefer stereo media playback volume; never leave mic monitoring paths open.
        player.audio?.volume = 100
        player.audio?.isMuted = false
        context.coordinator.player = player
        context.coordinator.onPlaybackFailed = onPlaybackFailed
        context.coordinator.onPlaying = onPlaying
        context.coordinator.startRouteObserver()
        context.coordinator.apply(url: url, headers: headers, play: isPlaying)
        return host
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        context.coordinator.onPlaybackFailed = onPlaybackFailed
        context.coordinator.onPlaying = onPlaying
        context.coordinator.apply(url: url, headers: headers, play: isPlaying)
    }

    static func dismantleUIView(_ uiView: PlayerHostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        var player: VLCMediaPlayer?
        var onPlaybackFailed: (() -> Void)?
        var onPlaying: (() -> Void)?
        private var currentURL: URL?
        private var routeObserver: NSObjectProtocol?
        private var lastFailReportAt: Date = .distantPast
        private var hasReachedPlaying = false
        private var failWorkItem: DispatchWorkItem?

        init(onPlaybackFailed: (() -> Void)?, onPlaying: (() -> Void)?) {
            self.onPlaybackFailed = onPlaybackFailed
            self.onPlaying = onPlaying
        }

        func startRouteObserver() {
            guard routeObserver == nil else { return }
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                LiveAudioSession.reassertCategory()
                guard let player = self?.player, player.isPlaying else { return }
                player.audio?.isMuted = false
            }
        }

        func apply(url: URL, headers: [String: String], play: Bool) {
            if !Thread.isMainThread {
                DispatchQueue.main.async { [weak self] in
                    self?.apply(url: url, headers: headers, play: play)
                }
                return
            }
            guard let player else { return }
            if currentURL != url {
                currentURL = url
                hasReachedPlaying = false
                LiveAudioSession.reassertCategory()
                if player.isPlaying {
                    player.stop()
                }
                let media = VLCMedia(url: url)
                func clean(_ s: String) -> String {
                    s.replacingOccurrences(of: "\r", with: "")
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let ua = headers["User-Agent"], !ua.isEmpty {
                    media.addOption(":http-user-agent=\(clean(ua))")
                }
                if let ref = headers["Referer"], !ref.isEmpty {
                    media.addOption(":http-referrer=\(clean(ref))")
                }
                if let origin = headers["Origin"], !origin.isEmpty {
                    media.addOption(":http-header=Origin: \(clean(origin))")
                }
                if let cookie = headers["Cookie"], !cookie.isEmpty {
                    var c = clean(cookie)
                    if c.count > 512 { c = String(c.prefix(512)) }
                    media.addOption(":http-header=Cookie: \(c)")
                }
                // Live-friendly buffering / reconnect (SimpleLive media_kit style).
                media.addOption(":network-caching=1500")
                media.addOption(":live-caching=1500")
                media.addOption(":clock-jitter=0")
                media.addOption(":clock-synchro=0")
                media.addOption(":no-audio-time-stretch")
                media.addOption(":http-reconnect")
                media.addOption(":http-continuous")
                media.addOption(":avcodec-hw=none")
                player.media = media
            }
            if play {
                if !player.isPlaying {
                    LiveAudioSession.reassertCategory()
                    player.audio?.isMuted = false
                    player.play()
                }
            } else {
                player.pause()
            }
        }

        func stop() {
            if !Thread.isMainThread {
                DispatchQueue.main.async { [weak self] in self?.stop() }
                return
            }
            failWorkItem?.cancel()
            failWorkItem = nil
            if let routeObserver {
                NotificationCenter.default.removeObserver(routeObserver)
                self.routeObserver = nil
            }
            player?.delegate = nil
            player?.stop()
            player?.media = nil
            player?.drawable = nil
            player = nil
            currentURL = nil
            LiveAudioSession.deactivateIfNeeded()
        }

        // MARK: VLCMediaPlayerDelegate

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let player else { return }
            let state = player.state
            // Use raw values loosely — MobileVLCKit state set varies slightly by version.
            switch state {
            case .playing:
                if !hasReachedPlaying {
                    hasReachedPlaying = true
                    onPlaying?()
                }
            case .error:
                reportFailure(reason: "vlc_error")
            case .ended:
                // Live should not end; treat as stall / disconnect.
                if hasReachedPlaying {
                    reportFailure(reason: "vlc_ended")
                }
            case .stopped:
                // Ignore stop during intentional media swap / teardown.
                break
            default:
                // Some builds report buffering/opening/esAdded; treat esAdded-like as playing once.
                if String(describing: state).lowercased().contains("esadded") ||
                    String(describing: state).lowercased().contains("playing") {
                    if !hasReachedPlaying {
                        hasReachedPlaying = true
                        onPlaying?()
                    }
                }
            }
        }

        private func reportFailure(reason: String) {
            // Debounce burst errors from LibVLC.
            let now = Date()
            guard now.timeIntervalSince(lastFailReportAt) > 1.5 else { return }
            lastFailReportAt = now
            failWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onPlaybackFailed?()
            }
            failWorkItem = work
            // Small delay so intentional stop() during URL swap doesn't fire reconnect.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    /// Drawable host for VLC (must be a plain UIView).
    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { CALayer.self }
    }
}

#else

/// Stub when MobileVLCKit is not linked (e.g. open source tree without `pod install`).
struct LiveVLCPlayerView: View {
    let url: URL
    var headers: [String: String] = [:]
    var isPlaying: Bool = true
    var onPlaybackFailed: (() -> Void)? = nil
    var onPlaying: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Image(systemName: "play.slash")
                    .foregroundStyle(.white.opacity(0.7))
                Text("需要 MobileVLCKit（pod install）")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .onAppear {
            if isPlaying { LiveAudioSession.activateForPlayback() }
        }
    }
}

#endif
