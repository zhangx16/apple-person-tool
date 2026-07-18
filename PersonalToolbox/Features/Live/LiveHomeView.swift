import SwiftUI
import WebKit

/// Live tab v2.4 — web-only, zero native live stack.
///
/// Native SimpleLive port (services / danmaku / AVPlayer / JSCore) is **not compiled**
/// into this build because it crashed on tab switch on newer iOS. This UI only
/// embeds mobile live sites in WKWebView after an explicit user tap (never during
/// the TabView transition).
struct LiveHomeView: View {
    private enum Site: String, CaseIterable, Identifiable {
        case bilibili, huya, douyu, douyin, kuaishou
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bilibili: return "哔哩哔哩"
            case .huya: return "虎牙"
            case .douyu: return "斗鱼"
            case .douyin: return "抖音"
            case .kuaishou: return "快手"
            }
        }

        var systemImage: String {
            switch self {
            case .bilibili: return "play.rectangle.fill"
            case .huya: return "gamecontroller.fill"
            case .douyu: return "tv.fill"
            case .douyin: return "music.note"
            case .kuaishou: return "video.fill"
            }
        }

        var homeURL: URL {
            switch self {
            case .bilibili: return URL(string: "https://live.bilibili.com")!
            case .huya: return URL(string: "https://m.huya.com")!
            case .douyu: return URL(string: "https://m.douyu.com")!
            case .douyin: return URL(string: "https://live.douyin.com")!
            case .kuaishou: return URL(string: "https://live.kuaishou.com")!
            }
        }
    }

    @State private var site: Site = .bilibili
    /// nil = no WKWebView in hierarchy (safest for TabView).
    @State private var activeURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("直播")
                        .font(.title2.bold())
                    Text("v2.4 网页模式")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if activeURL != nil {
                    Button {
                        activeURL = nil
                    } label: {
                        Text("关闭页面")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Site.allCases) { s in
                        let on = site == s
                        Button {
                            site = s
                            // Do not auto-create WebView on platform switch.
                            if activeURL != nil {
                                activeURL = s.homeURL
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: s.systemImage)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(s.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            Divider()

            if let url = activeURL {
                LiveWKWebView(url: url)
                    .id(url.absoluteString)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "tv")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text(site.title)
                        .font(.headline)
                    Text("为避免闪退，直播改为系统网页打开。\n点下方按钮加载（不会在切换 Tab 时自动加载）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Button {
                        activeURL = site.homeURL
                    } label: {
                        Text("打开 \(site.title) 直播")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 32)

                    Link(destination: site.homeURL) {
                        Text("或用 Safari 打开")
                            .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
        // Intentionally no onAppear network / WebView creation.
    }
}

// MARK: - WKWebView

struct LiveWKWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        web.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.loadedURL = url
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let scheme = navigationAction.request.url?.scheme?.lowercased(),
               scheme != "http", scheme != "https", scheme != "about" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
