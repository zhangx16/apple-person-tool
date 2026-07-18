import SwiftUI
import UIKit

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
        let player = VLCMediaPlayer()
        player.drawable = host
        context.coordinator.player = player
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

        func apply(url: URL, headers: [String: String], play: Bool) {
            guard let player else { return }
            if currentURL != url {
                currentURL = url
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
                player.media = media
            }
            if play {
                if !player.isPlaying {
                    player.play()
                }
            } else {
                player.pause()
            }
        }

        func stop() {
            player?.stop()
            player?.media = nil
            player?.drawable = nil
            player = nil
            currentURL = nil
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
    }
}

#endif
