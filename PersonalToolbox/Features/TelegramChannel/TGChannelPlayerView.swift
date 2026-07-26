import AVKit
import AVFoundation
import SwiftUI
import UIKit

/// Full-screen landscape player for tg-channel-api `/play` streams.
/// Progressive HTTP (Range) + token query — does **not** download the whole multi‑GB file first.
struct TGChannelPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// Absolute progressive URL (includes `?token=`).
    let streamURL: URL
    /// Optional size hint for status text.
    var fileSizeHint: Int64? = nil

    @State private var player: AVPlayer?
    @State private var statusText = "连接中…"
    @State private var errorText: String?
    @State private var isReady = false
    @State private var itemObserver: NSKeyValueObservation?
    @State private var statusObserver: NSKeyValueObservation?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let player {
                TGStreamPlayerRepresentable(player: player)
                    .ignoresSafeArea()
            }

            if !isReady {
                VStack(spacing: 12) {
                    if errorText == nil {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.15)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                    }
                    Text(errorText ?? statusText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    if let errorText {
                        Button("重试") {
                            self.errorText = nil
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                        .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                tearDown()
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
        statusText = sizeStatusPrefix() + "缓冲首段…"
        errorText = nil
        isReady = false
        tearDownPlayerOnly()

        _ = DownloadPlaybackAudio.activate()

        // Prefer progressive streaming. Server supports Range + inline disposition.
        let asset = AVURLAsset(url: streamURL)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
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
                    statusText = sizeStatusPrefix() + "解析中…"
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

        // Safety timeout so UI never spins forever on dead endpoints.
        // First-hit uncached multi-GB files may still take a while server-side.
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if isReady || errorText != nil { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if !isReady, errorText == nil {
            errorText = "加载超时（大文件首次会先从 Telegram 拉到服务器缓存，可稍后重试）"
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

// MARK: - AVPlayerViewController host (system chrome, PiP-ready)

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
