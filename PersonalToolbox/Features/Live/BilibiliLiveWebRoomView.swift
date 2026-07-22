import SwiftUI
import WebKit
import AVFoundation

/// Isolated B站直播页：只开 H5 + 可选轻量标题刷新。
/// 刻意不复用 `LiveRoomView` / VLC / AVPlayer 拉流链路（多机型硬崩）。
struct BilibiliLiveWebRoomView: View {
    let room: LiveRoomItem
    @Environment(\.dismiss) private var dismiss
    @State private var titleText: String = ""
    @State private var subtitleText: String = ""
    @State private var statusText: String = "加载网页…"
    @State private var isLive: Bool?
    @State private var loadError: String?

    private var pageURL: URL {
        let raw = room.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let rid = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
        if let u = URL(string: "https://live.bilibili.com/h5/\(rid)") { return u }
        if let u = URL(string: "https://live.bilibili.com/\(rid)") { return u }
        return URL(string: "https://live.bilibili.com") ?? URL(fileURLWithPath: "/")
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                BilibiliH5WebView(url: pageURL)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LivePlatformMark(platform: .bilibili, size: 22)
                    Text("B站直播")
                        .font(.subheadline.weight(.semibold))
                    if let isLive {
                        Text(isLive ? "直播中" : "未开播")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isLive ? Color.red : Color.gray, in: Capsule())
                    }
                    Spacer()
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(titleText.isEmpty ? (room.title.isEmpty ? "房间 \(room.roomId)" : room.title) : titleText)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                if !subtitleText.isEmpty || !room.userName.isEmpty {
                    Text(subtitleText.isEmpty ? room.userName : subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("房间号 \(room.roomId)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let loadError, !loadError.isEmpty {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("B站使用网页播放（H5），避免应用内解码崩溃。可在系统浏览器中打开同房间。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        UIApplication.shared.open(pageURL)
                    } label: {
                        Label("系统浏览器打开", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        statusText = "刷新网页…"
                        // Force reload by toggling identity via notification to web view is heavy;
                        // re-present same URL is enough for most cases — user can pull dismiss/reopen.
                        statusText = "请下拉关闭后重进，或用系统浏览器"
                    } label: {
                        Label("提示", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))

            Spacer(minLength: 0)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(room.userName.isEmpty ? "B站直播" : room.userName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { dismiss() }
            }
        }
        .task {
            await refreshMeta()
        }
    }

    private func refreshMeta() async {
        let rid = room.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return }
        statusText = "读取房间信息…"
        do {
            let detail = try await BilibiliLiveService.shared.getRoomDetail(roomId: rid)
            await MainActor.run {
                titleText = detail.title
                subtitleText = detail.userName
                isLive = detail.isLive
                statusText = detail.isLive ? "网页播放中" : "未开播 · 网页可试"
                loadError = nil
            }
        } catch {
            await MainActor.run {
                statusText = "网页可直接试播"
                loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Lightweight WKWebView (no LiveAudioSession coupling beyond best-effort)

private struct BilibiliH5WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        // Best-effort audio session; ignore failures.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.websiteDataStore = .default()
        if #available(iOS 14.0, *) {
            config.processPool = WKProcessPool()
        }
        if #available(iOS 15.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.bounces = true
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.loaded = url
        web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loaded != url {
            context.coordinator.loaded = url
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.evaluateJavaScript(
            "document.querySelectorAll('video,audio').forEach(function(e){try{e.pause();e.removeAttribute('src');e.load();}catch(_){}})",
            completionHandler: nil
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: URL?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let u = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let scheme = (u.scheme ?? "").lowercased()
            // Keep http(s) / about / blob; block app-store deep links that can suspend the app oddly.
            if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "blob" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Soft fail — page may still partially render.
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        }
    }
}
