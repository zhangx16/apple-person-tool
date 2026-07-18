import SwiftUI
import AVKit

/// Full-screen system player (`AVPlayerViewController`) for downloaded media.
struct SystemVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        let player = AVPlayer(url: url)
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        context.coordinator.player = player
        player.play()
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

/// Sheet wrapper with a close button for list/task playback.
struct VideoPlayerSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SystemVideoPlayer(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            dismiss()
                        }
                    }
                }
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
