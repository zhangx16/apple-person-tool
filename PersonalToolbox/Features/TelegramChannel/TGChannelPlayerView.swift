import AVKit
import AVFoundation
import SwiftUI
import UIKit

/// Full-screen landscape player for tg-channel-api `/play` streams.
/// Progressive HTTP: server streams from Telegram while caching (no full wait on first play).
struct TGChannelPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// Absolute progressive URL (includes `?token=`).
    let streamURL: URL
    /// Optional size hint for status text.
    var fileSizeHint: Int64? = nil
    /// When false, server is still pulling from Telegram (edge-play).
    var wasCached: Bool = false

    @State private var player: AVPlayer?
    @State private var statusText = "连接中…"
    @State private var errorText: String?
    @State private var isReady = false
    @State private var itemObserver: NSKeyValueObservation?
    @State private var statusObserver: NSKeyValueObservation?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                TGStreamPlayerRepresentable(player: player)
                    .ignoresSafeArea()
            }

            if !isReady {
                VStack(spacing: 14) {
                    if errorText == nil {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                    }
                    Text(errorText ?? statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    if errorText == nil, !wasCached {
                        Text("边下边播 · 服务器从 Telegram 拉取并缓存")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    if errorText != nil {
                        Button("重试") {
                            self.errorText = nil
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.22))
                        .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Close — top leading, safe for landscape notch.
            VStack {
                HStack {
                    Button {
                        tearDown()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.95), .black.opacity(0.4))
                            .padding(16)
                    }
                    .accessibilityLabel("关闭播放")
                    Spacer()
                }
                Spacer()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            await load()
        }
        .onAppear {
            _ = DownloadPlaybackAudio.activate()
            OrientationHelper.lockLandscape()
        }
        .onDisappear {
            tearDown()
            DownloadPlaybackAudio.deactivate()
            OrientationHelper.lockPortrait()
        }
    }

    private func load() async {
        statusText = wasCached
            ? (sizeStatusPrefix() + "缓冲首段…")
            : (sizeStatusPrefix() + "边下边播，连接中…")
        errorText = nil
        isReady = false
        tearDownPlayerOnly()

        _ = DownloadPlaybackAudio.activate()

        let asset = AVURLAsset(url: streamURL)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 6
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        player = p

        itemObserver = item.observe(\.status, options: [.initial, .new]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    statusText = "播放中"
                    isReady = true
                    errorText = nil
                    p.play()
                case .failed:
                    let msg = item.error?.localizedDescription ?? "无法打开视频流"
                    errorText = msg
                    isReady = false
                    statusText = "加载失败"
                case .unknown:
                    statusText = wasCached
                        ? (sizeStatusPrefix() + "解析中…")
                        : (sizeStatusPrefix() + "服务器拉取中…")
                @unknown default:
                    break
                }
            }
        }
        statusObserver = p.observe(\.timeControlStatus, options: [.new]) { player, _ in
            Task { @MainActor in
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    if isReady { statusText = "缓冲中…" }
                case .playing:
                    if isReady { statusText = "播放中" }
                default:
                    break
                }
            }
        }

        // Progressive first-byte can take longer for large TG media.
        let deadline = Date().addingTimeInterval(wasCached ? 60 : 180)
        while Date() < deadline {
            if isReady || errorText != nil { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        if !isReady, errorText == nil {
            errorText = wasCached
                ? "加载超时，请检查网络后重试"
                : "加载超时：服务器仍在从 Telegram 拉流，可稍后重试（已下部分会保留为缓存）"
        }
    }

    private func sizeStatusPrefix() -> String {
        guard let n = fileSizeHint, n > 0 else { return "" }
        let mb = Double(n) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB · ", mb / 1024)
        }
        return String(format: "%.0f MB · ", mb)
    }

    private func tearDownPlayerOnly() {
        itemObserver?.invalidate()
        itemObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func tearDown() {
        tearDownPlayerOnly()
    }
}

// MARK: - AVPlayerViewController host

private struct TGStreamPlayerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        _ = DownloadPlaybackAudio.activate()
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        vc.allowsPictureInPicturePlayback = true
        if #available(iOS 14.0, *) {
            vc.canStartPictureInPictureAutomaticallyFromInline = true
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        _ = DownloadPlaybackAudio.activate()
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
}
