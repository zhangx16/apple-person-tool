import SwiftUI
import AVKit
import UIKit

/// Full-screen system player (`AVPlayerViewController`) for downloaded media.
/// Uses iOS built-in controls (scrubber, PiP, AirPlay, speed when available).
struct SystemVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    /// Auto-start playback when presented.
    var autoplay: Bool = true

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        let player = AVPlayer(url: url)
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        vc.allowsPictureInPicturePlayback = true
        if #available(iOS 14.0, *) {
            vc.canStartPictureInPictureAutomaticallyFromInline = true
        }
        // Prefer landscape fullscreen chrome when the system offers it.
        if #available(iOS 16.0, *) {
            vc.allowsVideoFrameAnalysis = true
        }
        context.coordinator.player = player
        if autoplay {
            player.play()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
        uiViewController.player = nil
        coordinator.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVPlayer?
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

            // Native player fills the screen; keep a light dismiss control in landscape.
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
            OrientationHelper.lockLandscape()
        }
        .onDisappear {
            OrientationHelper.lockPortrait()
        }
    }
}

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
