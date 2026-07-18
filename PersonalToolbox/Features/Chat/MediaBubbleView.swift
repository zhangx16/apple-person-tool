import SwiftUI
import AVKit

/// Image / video bubble with Share Sheet export (K18).
struct MediaBubbleView: View {
    let message: ChatMessage
    var onCopyCaption: (() -> Void)?

    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var loadFailed = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                mediaBody
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
                }
            }
            if !isUser { Spacer(minLength: 48) }
        }
        .contextMenu {
            if shareableURL != nil || message.mediaRemoteURL != nil {
                Button {
                    prepareShare()
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
            if !message.content.isEmpty {
                Button {
                    onCopyCaption?()
                } label: {
                    Label("复制说明", systemImage: "doc.on.doc")
                }
            }
            if let remote = message.mediaRemoteURL, let url = URL(string: remote) {
                Button {
                    UIPasteboard.general.string = remote
                    Haptics.success()
                } label: {
                    Label("复制链接", systemImage: "link")
                }
                Link(destination: url) {
                    Label("在浏览器打开", systemImage: "safari")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(activityItems: shareItems)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Media content

    @ViewBuilder
    private var mediaBody: some View {
        // Failure / timeout / cancel before pending: request_id is retained for retry
        // but must not trap the bubble in a ProgressView (Issue 1).
        if message.isMediaFailed {
            failedCard
        } else if message.isMediaPending {
            pendingCard
        } else if !(message.videoPath ?? "").isEmpty || (message.mediaKind == .video && !(message.mediaRemoteURL ?? "").isEmpty) {
            videoCard
        } else if message.mediaKind == .image || !(message.imagePath ?? "").isEmpty {
            imageCard
        } else if message.mediaKind == .video {
            // Video row without file and not in-progress → show caption as failed-style card.
            failedCard
        } else {
            EmptyView()
        }
    }

    private var pendingCard: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(message.content.isEmpty ? "媒体生成中…" : message.content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 220, height: 160)
        .background(AppleTheme.assistantBubble, in: RoundedRectangle(cornerRadius: AppleTheme.bubbleRadius, style: .continuous))
    }

    private var failedCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message.content)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .background(AppleTheme.assistantBubble, in: RoundedRectangle(cornerRadius: AppleTheme.bubbleRadius, style: .continuous))
    }

    @ViewBuilder
    private var imageCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let uiImage = loadUIImage() {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 360)
                } else if let remote = message.mediaRemoteURL, let url = URL(string: remote) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().frame(width: 220, height: 160)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 280, maxHeight: 360)
                        case .failure:
                            failedPlaceholder(text: "图片加载失败")
                        @unknown default:
                            failedPlaceholder(text: "图片加载失败")
                        }
                    }
                } else {
                    failedPlaceholder(text: loadFailed ? "图片不可用" : "图片加载中…")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppleTheme.bubbleRadius, style: .continuous))

            if shareableURL != nil || message.mediaRemoteURL != nil {
                Button {
                    prepareShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(8)
                .accessibilityLabel("分享图片")
            }
        }
    }

    @ViewBuilder
    private var videoCard: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = shareableURL ?? remoteFileURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: 280, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: AppleTheme.bubbleRadius, style: .continuous))
            } else {
                failedPlaceholder(text: message.content.isEmpty ? "视频不可用" : message.content)
                    .frame(width: 280, height: 160)
            }

            if shareableURL != nil || message.mediaRemoteURL != nil {
                Button {
                    prepareShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(8)
                .accessibilityLabel("分享视频")
            }
        }
    }

    private func failedPlaceholder(text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 280)
        .padding(16)
        .background(AppleTheme.assistantBubble, in: RoundedRectangle(cornerRadius: AppleTheme.bubbleRadius, style: .continuous))
    }

    // MARK: - Helpers

    private var shareableURL: URL? {
        let candidates = [message.imagePath, message.videoPath].compactMap { $0 }
        for path in candidates {
            if let url = ImagineService.resolveLocalURL(path),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private var remoteFileURL: URL? {
        message.mediaRemoteURL.flatMap { URL(string: $0) }
    }

    private func loadUIImage() -> UIImage? {
        if let path = message.imagePath,
           let url = ImagineService.resolveLocalURL(path),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    private func prepareShare() {
        var items: [Any] = []
        if let url = shareableURL {
            items.append(url)
        } else if let image = loadUIImage() {
            items.append(image)
        } else if let remote = message.mediaRemoteURL {
            items.append(remote)
        }
        guard !items.isEmpty else { return }
        shareItems = items
        showShare = true
        Haptics.light()
    }

    private var accessibilityLabel: String {
        let role = isUser ? "我" : "助手"
        if message.isMediaPending { return "\(role)，媒体生成中" }
        if message.mediaKind == .video { return "\(role)，视频：\(message.content)" }
        if message.mediaKind == .image { return "\(role)，图片：\(message.content)" }
        return "\(role)：\(message.content)"
    }
}

// MARK: - UIActivityViewController wrapper

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
