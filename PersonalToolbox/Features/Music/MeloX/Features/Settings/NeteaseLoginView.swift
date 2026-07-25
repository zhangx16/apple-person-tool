import SwiftUI
import WebKit

struct NeteaseLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeloXSettings.self) private var settings
    @Environment(LibraryStore.self) private var library

    @State private var isLoading = true
    @State private var progress: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            NeteaseLoginWebView(
                isLoading: $isLoading,
                progress: $progress,
                onCookie: { cookie in
                    settings.cookie = cookie
                    Task {
                        await library.refresh(force: true)
                        dismiss()
                    }
                }
            )
            if isLoading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        }
        .navigationTitle("登录网易云音乐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", role: .cancel) { dismiss() }
            }
        }
    }
}

private struct NeteaseLoginWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var progress: Double
    var onCookie: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        context.coordinator.observe(web)
        web.load(URLRequest(url: URL(string: "https://music.163.com")!))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(uiView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: NeteaseLoginWebView
        private var progressObs: NSKeyValueObservation?
        private var pollTask: Task<Void, Never>?

        init(parent: NeteaseLoginWebView) { self.parent = parent }

        func observe(_ web: WKWebView) {
            progressObs = web.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
                DispatchQueue.main.async {
                    self?.parent.progress = web.estimatedProgress
                    self?.parent.isLoading = web.isLoading
                }
            }
            pollTask = Task { @MainActor in
                while !Task.isCancelled {
                    if let header = await NeteaseWebCookieStore.authenticatedCookieHeader() {
                        parent.onCookie(header)
                        return
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }

        func teardown(_ web: WKWebView) {
            progressObs?.invalidate()
            pollTask?.cancel()
            web.navigationDelegate = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
    }
}

@MainActor
enum NeteaseWebCookieStore {
    private static let dataStore = WKWebsiteDataStore.default()

    static func authenticatedCookieHeader() async -> String? {
        let cookies = await allCookies().filter(isUsableNeteaseCookie)
        guard cookies.contains(where: { $0.name == "MUSIC_U" && !$0.value.isEmpty }) else {
            return nil
        }
        let values = cookies.reduce(into: [String: String]()) { result, cookie in
            result[cookie.name] = cookie.value
        }
        return values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }.joined(separator: "; ")
    }

    static func clear() async {
        for cookie in await allCookies() where isNeteaseCookie(cookie) {
            await dataStore.httpCookieStore.deleteCookie(cookie)
        }
    }

    private static func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func isUsableNeteaseCookie(_ cookie: HTTPCookie) -> Bool {
        isNeteaseCookie(cookie) && (cookie.expiresDate.map { $0 > Date() } ?? true)
    }

    private static func isNeteaseCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "163.com" || domain.hasSuffix(".163.com") || domain.contains("music.163.com")
    }
}
