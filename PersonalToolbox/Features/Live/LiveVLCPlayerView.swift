import SwiftUI
import UIKit
import AVFoundation

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

#if canImport(MobileVLCKit)
import MobileVLCKit

/// In-app player for HTTP-FLV / HLS (LibVLC).
/// Mirrors SimpleLive's media_kit role: decode streams AVPlayer rejects.
struct LiveVLCPlayerView: UIViewRepresentable {
    let url: URL
    var headers: [String: String] = [:]
    var isPlaying: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerHostView {
        let host = PlayerHostView()
        host.backgroundColor = .black
        LiveAudioSession.activateForPlayback()
        let player = VLCMediaPlayer()
        player.drawable = host
        // Prefer stereo media playback volume; never leave mic monitoring paths open.
        player.audio?.volume = 100
        player.audio?.isMuted = false
        context.coordinator.player = player
        context.coordinator.startRouteObserver()
        context.coordinator.apply(url: url, headers: headers, play: isPlaying)
        return host
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        context.coordinator.apply(url: url, headers: headers, play: isPlaying)
    }

    static func dismantleUIView(_ uiView: PlayerHostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var player: VLCMediaPlayer?
        private var currentURL: URL?
        private var routeObserver: NSObjectProtocol?

        func startRouteObserver() {
            guard routeObserver == nil else { return }
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Headphone plug/unplug can flip iOS to HFP; re-pin playback + A2DP.
                LiveAudioSession.reassertCategory()
                guard let player = self?.player, player.isPlaying else { return }
                // Nudge audio pipeline after route change so a second delayed path is not left open.
                player.audio?.isMuted = false
            }
        }

        func apply(url: URL, headers: [String: String], play: Bool) {
            guard let player else { return }
            if currentURL != url {
                currentURL = url
                LiveAudioSession.reassertCategory()
                let media = VLCMedia(url: url)
                // HTTP headers for CDN anti-leech (Huya / Douyu / Kuaishou).
                if let ua = headers["User-Agent"], !ua.isEmpty {
                    media.addOption(":http-user-agent=\(ua)")
                }
                if let ref = headers["Referer"], !ref.isEmpty {
                    media.addOption(":http-referrer=\(ref)")
                }
                if let origin = headers["Origin"], !origin.isEmpty {
                    media.addOption(":http-header=Origin: \(origin)")
                }
                if let cookie = headers["Cookie"], !cookie.isEmpty {
                    media.addOption(":http-header=Cookie: \(cookie)")
                }
                // Live stream: low cache, reconnect friendly.
                media.addOption(":network-caching=1000")
                media.addOption(":live-caching=1000")
                media.addOption(":clock-jitter=0")
                media.addOption(":clock-synchro=0")
                // Avoid time-stretch resampling artifacts that read as a delayed "echo" on headsets.
                media.addOption(":no-audio-time-stretch")
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
            if let routeObserver {
                NotificationCenter.default.removeObserver(routeObserver)
                self.routeObserver = nil
            }
            player?.stop()
            player?.media = nil
            player?.drawable = nil
            player = nil
            currentURL = nil
            LiveAudioSession.deactivateIfNeeded()
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
