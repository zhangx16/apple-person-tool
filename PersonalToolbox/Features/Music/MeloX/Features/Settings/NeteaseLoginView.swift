import SwiftUI
import WebKit

/// 网易云登录：优先手动粘贴 Cookie；网页登录仅作辅助（自动抓取在 WKWebView 上经常拿不到 HttpOnly）。
struct NeteaseLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MeloXSettings.self) private var settings
    @Environment(LibraryStore.self) private var library

    @State private var cookieDraft: String = ""
    @State private var statusText: String = "推荐直接粘贴 Cookie（最稳定）"
    @State private var isSaving = false
    @State private var showWebLogin = false
    @State private var webLoading = false
    @State private var webProgress: Double = 0
    @State private var webDetectStatus: String = "等待登录…"

    var body: some View {
        List {
            Section {
                Text(
                    "网易云把关键登录态放在 HttpOnly Cookie 里，App 内网页经常读不全。建议在浏览器登录后复制 Cookie，粘贴到下方。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField(
                    "粘贴完整 Cookie（至少含 MUSIC_U）",
                    text: $cookieDraft,
                    axis: .vertical
                )
                .lineLimit(4...12)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))

                if !cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cookieHint
                }

                Button {
                    Task { await saveManualCookie() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("保存 Cookie 并登录")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isSaving || !looksLikeCookie(cookieDraft))
            } header: {
                Text("手动输入 Cookie")
            } footer: {
                Text(
                    """
                    获取方式（任选）：
                    1. 电脑浏览器打开 music.163.com 并登录
                    2. F12 → Network → 任意请求 → Request Headers → Cookie 整段复制
                    3. 或扩展/开发者工具 Application → Cookies → 复制 MUSIC_U 等字段

                    至少需要 MUSIC_U；有 __csrf 更稳。
                    """
                )
            }

            Section {
                Toggle("显示网页登录（辅助）", isOn: $showWebLogin)
                if showWebLogin {
                    Text(webDetectStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .top) {
                        NeteaseLoginWebView(
                            isLoading: $webLoading,
                            progress: $webProgress,
                            detectStatus: $webDetectStatus,
                            onCookie: { cookie in
                                cookieDraft = cookie
                                Task { await saveManualCookie(raw: cookie) }
                            }
                        )
                        .frame(minHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if webLoading {
                            ProgressView(value: webProgress)
                                .progressViewStyle(.linear)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    Button("重新检测网页 Cookie") {
                        Task {
                            if let header = await NeteaseWebCookieStore.authenticatedCookieHeader() {
                                cookieDraft = header
                                webDetectStatus = "已检测到 Cookie，可点上方保存"
                            } else {
                                webDetectStatus = "仍未检测到 MUSIC_U，请登录后重试或改用手动粘贴"
                            }
                        }
                    }
                }
            } header: {
                Text("网页辅助登录")
            } footer: {
                Text("若网页里已登录但一直检测不到，请改用上方手动粘贴。")
            }

            Section {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("登录网易云音乐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", role: .cancel) { dismiss() }
            }
        }
        .onAppear {
            let existing = settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
            if !existing.isEmpty {
                cookieDraft = existing
                statusText = "已载入本机保存的 Cookie，可修改后重新保存"
            }
        }
    }

    @ViewBuilder
    private var cookieHint: some View {
        let parsed = NeteaseCookieParser.parse(cookieDraft)
        HStack(spacing: 12) {
            labelPill("MUSIC_U", ok: parsed.hasMusicU)
            labelPill("__csrf", ok: parsed.hasCsrf)
            if parsed.pairCount > 0 {
                Text("\(parsed.pairCount) 项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labelPill(_ title: String, ok: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(ok ? Color.white : Color.secondary)
            .background(ok ? Color.green : Color(.tertiarySystemFill), in: Capsule())
    }

    private func looksLikeCookie(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 8 else { return false }
        // Full header or bare MUSIC_U token
        return t.contains("MUSIC_U=") || t.contains("=") || t.count > 20
    }

    @MainActor
    private func saveManualCookie(raw: String? = nil) async {
        isSaving = true
        defer { isSaving = false }

        let normalized = NeteaseCookieParser.normalize(raw ?? cookieDraft)
        guard !normalized.isEmpty else {
            statusText = "Cookie 为空"
            return
        }
        let parsed = NeteaseCookieParser.parse(normalized)
        guard parsed.hasMusicU else {
            statusText = "未找到 MUSIC_U。请粘贴完整 Cookie，或至少包含 MUSIC_U=…"
            return
        }

        settings.cookie = normalized
        cookieDraft = normalized
        statusText = "已保存，正在同步音乐库…"
        await library.refresh(force: true)
        if library.isLoggedIn {
            statusText = "登录成功"
            dismiss()
        } else if let err = library.errorMessage, !err.isEmpty {
            statusText = "Cookie 已保存，但同步失败：\(err)"
        } else {
            // Cookie 有了但 profile 还没出来，也先关掉，列表会再刷
            statusText = "Cookie 已保存"
            dismiss()
        }
    }
}

// MARK: - Cookie parsing

enum NeteaseCookieParser {
    struct Result {
        var pairs: [String: String]
        var hasMusicU: Bool { !(pairs["MUSIC_U"] ?? "").isEmpty }
        var hasCsrf: Bool { !(pairs["__csrf"] ?? "").isEmpty }
        var pairCount: Int { pairs.count }
    }

    /// Accept full Cookie header or a bare MUSIC_U token.
    static func normalize(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip common prefixes when users paste from DevTools
        if t.lowercased().hasPrefix("cookie:") {
            t = String(t.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Newlines / multiple spaces → single header form
        t = t
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "; ")
            .replacingOccurrences(of: "\t", with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        while t.contains("; ;") { t = t.replacingOccurrences(of: "; ;", with: ";") }

        let parsed = parse(t)
        if parsed.hasMusicU {
            return parsed.pairs.keys.sorted().map { "\($0)=\(parsed.pairs[$0] ?? "")" }.joined(separator: "; ")
        }
        // Bare token without key
        if !t.contains("="), t.count > 16 {
            return "MUSIC_U=\(t)"
        }
        return t
    }

    static func parse(_ raw: String) -> Result {
        var pairs: [String: String] = [:]
        let parts = raw.split(separator: ";")
        for part in parts {
            let s = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            if let eq = s.firstIndex(of: "=") {
                let k = String(s[..<eq]).trimmingCharacters(in: .whitespaces)
                let v = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { pairs[k] = v }
            }
        }
        return Result(pairs: pairs)
    }
}

// MARK: - Optional web assist

private struct NeteaseLoginWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var detectStatus: String
    var onCookie: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Non-persistent store avoids clashing with other WKWebViews; cookies still readable via store API.
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        // Mobile site is more likely to complete login in-app.
        web.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.observe(web)
        web.load(URLRequest(url: URL(string: "https://music.163.com/m/login")!))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(uiView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: NeteaseLoginWebView
        private var progressObs: NSKeyValueObservation?
        private var pollTask: Task<Void, Never>?
        private var didFire = false
        private weak var webView: WKWebView?

        init(parent: NeteaseLoginWebView) { self.parent = parent }

        func observe(_ web: WKWebView) {
            webView = web
            progressObs = web.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
                DispatchQueue.main.async {
                    self?.parent.progress = web.estimatedProgress
                    self?.parent.isLoading = web.isLoading
                }
            }
            pollTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var ticks = 0
                while !Task.isCancelled {
                    ticks += 1
                    await self.probeCookies(reason: "poll")
                    if self.didFire { return }
                    if ticks % 4 == 0 {
                        self.parent.detectStatus = "检测中…（登录后若仍无结果请改用手动粘贴）"
                    }
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }

        func teardown(_ web: WKWebView) {
            progressObs?.invalidate()
            pollTask?.cancel()
            web.navigationDelegate = nil
            web.uiDelegate = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            Task { await probeCookies(reason: "navigate") }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Popup login → same webview
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        @MainActor
        private func probeCookies(reason: String) async {
            guard !didFire else { return }
            // Prefer this webview's data store.
            if let store = webView?.configuration.websiteDataStore {
                if let header = await NeteaseWebCookieStore.authenticatedCookieHeader(from: store) {
                    didFire = true
                    parent.detectStatus = "已从网页检测到 Cookie（\(reason)）"
                    parent.onCookie(header)
                    return
                }
            }
            // Fallback: default store + JS-visible cookies (non-HttpOnly only).
            if let header = await NeteaseWebCookieStore.authenticatedCookieHeader() {
                didFire = true
                parent.detectStatus = "已检测到 Cookie（\(reason)）"
                parent.onCookie(header)
                return
            }
            if let webView {
                let js: String = await withCheckedContinuation { cont in
                    webView.evaluateJavaScript("document.cookie") { result, _ in
                        cont.resume(returning: (result as? String) ?? "")
                    }
                }
                if js.contains("MUSIC_U=") {
                    let normalized = NeteaseCookieParser.normalize(js)
                    if NeteaseCookieParser.parse(normalized).hasMusicU {
                        didFire = true
                        parent.detectStatus = "已从页面脚本读到 Cookie（可能不完整）"
                        parent.onCookie(normalized)
                    }
                }
            }
        }
    }
}

@MainActor
enum NeteaseWebCookieStore {
    private static let dataStore = WKWebsiteDataStore.default()

    static func authenticatedCookieHeader(
        from store: WKWebsiteDataStore = dataStore
    ) async -> String? {
        let cookies = await allCookies(from: store).filter(isUsableNeteaseCookie)
        // MUSIC_U is the real session; also accept MUSIC_A_T / MUSIC_R_T on some clients.
        let hasSession = cookies.contains {
            ($0.name == "MUSIC_U" || $0.name == "MUSIC_A_T" || $0.name == "MUSIC_R_T")
                && !$0.value.isEmpty
        }
        guard hasSession else { return nil }

        var values = cookies.reduce(into: [String: String]()) { result, cookie in
            result[cookie.name] = cookie.value
        }
        // Prefer renaming token-only sessions
        if values["MUSIC_U"] == nil, let at = values["MUSIC_A_T"], !at.isEmpty {
            values["MUSIC_U"] = at
        }
        guard let musicU = values["MUSIC_U"], !musicU.isEmpty else { return nil }
        _ = musicU
        return values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }.joined(separator: "; ")
    }

    static func clear() async {
        for cookie in await allCookies() where isNeteaseCookie(cookie) {
            await dataStore.httpCookieStore.deleteCookie(cookie)
        }
    }

    private static func allCookies(
        from store: WKWebsiteDataStore = dataStore
    ) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func isUsableNeteaseCookie(_ cookie: HTTPCookie) -> Bool {
        isNeteaseCookie(cookie) && (cookie.expiresDate.map { $0 > Date() } ?? true)
    }

    private static func isNeteaseCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "163.com"
            || domain.hasSuffix(".163.com")
            || domain.contains("music.163")
            || domain.contains("netease")
    }
}
