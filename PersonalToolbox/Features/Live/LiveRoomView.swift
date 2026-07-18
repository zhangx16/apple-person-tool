import SwiftUI
import AVFoundation
import AVKit
import WebKit
import UIKit

// MARK: - Room ViewModel

@MainActor
final class LiveRoomViewModel: ObservableObject {
    enum PlayMode: String, CaseIterable, Identifiable {
        /// App 内：VLC 播 FLV/HLS（对齐 SimpleLive media_kit 能力）
        case native = "应用内"
        case web = "网页"
        var id: String { rawValue }
    }

    let room: LiveRoomItem

    @Published var detail: LiveRoomDetail?
    @Published var qualities: [LivePlayQuality] = []
    @Published var selectedId: String?
    @Published var isLoading = true
    @Published var statusText: String = "正在连接…"
    @Published var errorMessage: String?
    @Published var playMode: PlayMode = .native
    @Published var webURL: URL?

    /// Active stream for VLC / AVPlayer.
    @Published var streamURL: URL?
    @Published var streamHeaders: [String: String] = [:]
    /// True when current stream is FLV (must use VLC).
    @Published private(set) var streamIsFLV = false

    private var loadTask: Task<Void, Never>?
    private var failWatchTask: Task<Void, Never>?
    private var headerLoader: LiveHeaderResourceLoader?
    private var avPlayer: AVPlayer?

    /// Exposed for rare AVPlayer fallback (HLS only, no VLC binary).
    var systemPlayer: AVPlayer? { avPlayer }

    init(room: LiveRoomItem) {
        self.room = room
        webURL = URL(string: defaultWebURL)
        // With VLC, FLV sites use in-app player by default.
        playMode = .native
    }

    private var defaultWebURL: String {
        switch room.platform {
        case .huya: return "https://m.huya.com/\(room.roomId)"
        case .douyu: return "https://m.douyu.com/\(room.roomId)"
        case .douyin: return "https://live.douyin.com/\(room.roomId)"
        case .kuaishou: return "https://live.kuaishou.com/u/\(room.roomId)"
        }
    }

    func start() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        failWatchTask?.cancel()
        failWatchTask = nil
        clearStream()
    }

    func retryNative() {
        playMode = .native
        errorMessage = nil
        start()
    }

    func switchToWeb() {
        clearStream()
        playMode = .web
        statusText = "网页播放"
        isLoading = false
    }

    private func clearStream() {
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
        headerLoader = nil
        streamURL = nil
        streamHeaders = [:]
        streamIsFLV = false
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        statusText = playMode == .web ? "加载网页直播…" : "获取房间信息…"
        defer { isLoading = false }

        do {
            let d = try await LiveSiteRouter.roomDetail(platform: room.platform, roomId: room.roomId)
            guard !Task.isCancelled else { return }
            detail = d
            if let u = URL(string: mobileWebURL(for: d)) {
                webURL = u
            } else if let u = URL(string: d.webURL), u.scheme == "http" || u.scheme == "https" {
                webURL = u
            }

            if playMode == .web {
                statusText = d.isLive ? "网页播放中" : "未开播 · 网页可试"
                Task { await warmQualities(detail: d) }
                return
            }

            statusText = d.isLive ? "解析播放地址…" : "主播未开播"
            guard d.isLive else {
                errorMessage = "当前未开播"
                playMode = .web
                return
            }

            let qs = try await LiveSiteRouter.playQualities(detail: d)
            guard !Task.isCancelled else { return }
            qualities = qs
            guard let first = qs.first else {
                statusText = "无播放线路，使用网页"
                playMode = .web
                return
            }
            selectedId = first.id
            await play(quality: first)
            scheduleAutoWebFallback()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            statusText = "信息加载失败，仍可试网页"
            playMode = .web
        }
    }

    private func mobileWebURL(for d: LiveRoomDetail) -> String {
        switch d.platform {
        case .huya: return "https://m.huya.com/\(d.roomId)"
        case .douyu: return "https://m.douyu.com/\(d.roomId)"
        case .douyin: return "https://live.douyin.com/\(d.roomId)"
        case .kuaishou: return "https://live.kuaishou.com/u/\(d.roomId)"
        }
    }

    private func warmQualities(detail: LiveRoomDetail) async {
        guard detail.isLive else { return }
        if let qs = try? await LiveSiteRouter.playQualities(detail: detail), !qs.isEmpty {
            qualities = qs
            if selectedId == nil { selectedId = qs.first?.id }
        }
    }

    func selectQuality(_ q: LivePlayQuality) {
        selectedId = q.id
        playMode = .native
        Task { await play(quality: q) }
    }

    private func play(quality: LivePlayQuality) async {
        guard let detail else { return }
        statusText = "拉取线路 \(quality.name)…"
        do {
            let result = try await LiveSiteRouter.playURLs(detail: detail, quality: quality)
            guard !Task.isCancelled else { return }

            // Prefer order: HLS first (lighter), then FLV (needs VLC), skip empty.
            let ordered = Self.rankURLs(result.urls)
            guard !ordered.isEmpty else {
                errorMessage = nil
                statusText = "无可用地址，使用网页"
                playMode = .web
                return
            }

            var lastErr: String?
            for urlString in ordered.prefix(6) {
                guard let url = URL(string: urlString) else { continue }
                let isFLV = urlString.lowercased().contains(".flv")
                statusText = isFLV ? "VLC 播放 FLV…" : "连接 \(quality.name)…"

                #if canImport(MobileVLCKit)
                // VLC handles both FLV and HLS.
                clearStream()
                streamHeaders = result.headers
                streamIsFLV = isFLV
                streamURL = url
                playMode = .native
                errorMessage = nil
                statusText = "播放中 · \(quality.name)" + (isFLV ? " · FLV" : " · HLS")
                return
                #else
                // No VLC: only try HLS via AVPlayer.
                if isFLV {
                    lastErr = "无 VLC，跳过 FLV"
                    continue
                }
                if await startAVPlayer(url: url, headers: result.headers) {
                    streamIsFLV = false
                    streamURL = url
                    streamHeaders = result.headers
                    playMode = .native
                    errorMessage = nil
                    statusText = "播放中 · \(quality.name)"
                    return
                }
                lastErr = "线路失败"
                #endif
            }

            #if canImport(MobileVLCKit)
            errorMessage = (lastErr ?? "播放失败") + "，可切网页"
            statusText = "播放失败"
            #else
            errorMessage = "当前包未集成 VLC，FLV 请用网页或重新 pod install"
            statusText = "改用网页"
            playMode = .web
            #endif
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            statusText = "拉流失败，可切网页"
        }
    }

    private static func rankURLs(_ urls: [String]) -> [String] {
        urls
            .filter { URL(string: $0) != nil }
            .sorted { a, b in
                let am = a.contains(".m3u8") || a.contains("m3u8")
                let bm = b.contains(".m3u8") || b.contains("m3u8")
                if am != bm { return am && !bm }
                let aflv = a.lowercased().contains(".flv")
                let bflv = b.lowercased().contains(".flv")
                // Prefer non-mcdn
                let amd = a.contains("mcdn")
                let bmd = b.contains("mcdn")
                if amd != bmd { return !amd && bmd }
                if aflv != bflv { return !aflv && bflv }
                return false
            }
    }

    private func startAVPlayer(url: URL, headers: [String: String]) async -> Bool {
        if await attachAV(
            asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        ) {
            return true
        }
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let originalScheme = comps.scheme ?? "https"
        comps.scheme = "livehdr"
        guard let proxyURL = comps.url else { return false }
        let loader = LiveHeaderResourceLoader(headers: headers, realScheme: originalScheme)
        headerLoader = loader
        let asset = AVURLAsset(url: proxyURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return await attachAV(asset: asset)
    }

    private func attachAV(asset: AVURLAsset) async -> Bool {
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = p
        p.play()
        try? await Task.sleep(nanoseconds: 900_000_000)
        if item.status == .failed {
            avPlayer = nil
            return false
        }
        return true
    }

    private func scheduleAutoWebFallback() {
        failWatchTask?.cancel()
        failWatchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            #if canImport(MobileVLCKit)
            // VLC path: only fall back if still loading with no URL.
            if self.playMode == .native, self.streamURL == nil, self.isLoading == false {
                self.statusText = "无画面，可手动切网页"
            }
            #else
            if self.playMode == .native, self.avPlayer == nil {
                self.switchToWeb()
            }
            #endif
        }
    }
}

// MARK: - Header-injecting resource loader (AVPlayer HLS)

final class LiveHeaderResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    let headers: [String: String]
    let realScheme: String
    let queue = DispatchQueue(label: "live.header.loader")

    init(headers: [String: String], realScheme: String) {
        self.headers = headers
        self.realScheme = realScheme
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url else {
            loadingRequest.finishLoading(with: URLError(.badURL))
            return true
        }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = realScheme
        guard let realURL = comps?.url else {
            loadingRequest.finishLoading(with: URLError(.badURL))
            return true
        }

        var req = URLRequest(url: realURL)
        req.httpMethod = loadingRequest.request.httpMethod ?? "GET"
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if let range = loadingRequest.request.value(forHTTPHeaderField: "Range") {
            req.setValue(range, forHTTPHeaderField: "Range")
        }

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                loadingRequest.finishLoading(with: URLError(.badServerResponse))
                return
            }
            if let info = loadingRequest.contentInformationRequest {
                info.isByteRangeAccessSupported = true
                if let mime = http.value(forHTTPHeaderField: "Content-Type") {
                    info.contentType = mime
                } else if realURL.pathExtension == "m3u8" {
                    info.contentType = "application/vnd.apple.mpegurl"
                } else {
                    info.contentType = "application/octet-stream"
                }
                if let len = http.value(forHTTPHeaderField: "Content-Length"), let n = Int64(len) {
                    info.contentLength = n
                } else {
                    info.contentLength = Int64(data.count)
                }
            }
            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        }
        task.resume()
        return true
    }
}

// MARK: - Room UI (full page; optional true fullscreen player)

struct LiveRoomView: View {
    let room: LiveRoomItem
    @StateObject private var vm: LiveRoomViewModel
    @ObservedObject private var follows = LiveFollowStore.shared
    @State private var isPlayerFullscreen = false

    init(room: LiveRoomItem) {
        self.room = room
        _vm = StateObject(wrappedValue: LiveRoomViewModel(room: room))
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
                .frame(minHeight: 240, maxHeight: 320)
                .background(Color.black)
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        isPlayerFullscreen = true
                    } label: {
                        Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .disabled(vm.streamURL == nil && vm.playMode == .native && vm.webURL == nil)
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("播放方式", selection: $vm.playMode) {
                        ForEach(LiveRoomViewModel.PlayMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.playMode) { _, mode in
                        if mode == .web {
                            vm.switchToWeb()
                        } else {
                            vm.retryNative()
                        }
                    }

                    infoArea
                    if vm.playMode == .native {
                        qualityPicker
                    }

                    Text(vm.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    #if canImport(MobileVLCKit)
                    Text("应用内：VLC 可播 FLV · 点播放器右下角全屏")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    #else
                    Text("未链接 VLC，FLV 将回退网页")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    #endif

                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button("重试应用内") { vm.retryNative() }
                            .buttonStyle(.bordered)
                        Button("网页") { vm.switchToWeb() }
                            .buttonStyle(.bordered)
                        Button {
                            isPlayerFullscreen = true
                        } label: {
                            Label("全屏播放", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        isPlayerFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel("全屏播放")

                    Button {
                        toggleFollow()
                    } label: {
                        Image(systemName: isFollowed ? "star.fill" : "star")
                            .foregroundStyle(isFollowed ? Color.yellow : Color.primary)
                    }
                }
            }
        }
        .task { vm.start() }
        // Only tear down when leaving the room page (not when entering fullscreen cover).
        .onDisappear {
            if !isPlayerFullscreen {
                vm.stop()
            }
        }
        .fullScreenCover(isPresented: $isPlayerFullscreen) {
            LiveRoomFullscreenView(vm: vm)
        }
    }

    private var navTitle: String {
        if let name = vm.detail?.userName, !name.isEmpty { return name }
        if !room.userName.isEmpty { return room.userName }
        return "直播间 \(room.roomId)"
    }

    private var isFollowed: Bool {
        follows.isFollowing(
            platform: vm.detail?.platform ?? room.platform,
            roomId: vm.detail?.roomId ?? room.roomId
        )
    }

    private func toggleFollow() {
        let item = LiveRoomItem(
            platform: vm.detail?.platform ?? room.platform,
            roomId: vm.detail?.roomId ?? room.roomId,
            title: vm.detail?.title ?? room.title,
            cover: vm.detail?.cover ?? room.cover,
            userName: vm.detail?.userName ?? room.userName,
            online: vm.detail?.online ?? room.online
        )
        if isFollowed {
            follows.unfollow(platform: item.platform, roomId: item.roomId)
        } else {
            follows.follow(item)
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        LivePlayerSurface(vm: vm)
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.detail?.title ?? (room.title.isEmpty ? "直播间 \(room.roomId)" : room.title))
                .font(.headline)
            HStack {
                Text(vm.detail?.userName ?? (room.userName.isEmpty ? platformTitle : room.userName))
                Spacer()
                if let d = vm.detail {
                    Text(d.isLive ? "直播中" : "未开播")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d.isLive ? Color.green : Color.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("\(platformTitle) · 房间 \(vm.detail?.roomId ?? room.roomId)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var platformTitle: String {
        (vm.detail?.platform ?? room.platform).title
    }

    @ViewBuilder
    private var qualityPicker: some View {
        if !vm.qualities.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(vm.qualities) { q in
                        Button {
                            vm.selectQuality(q)
                        } label: {
                            Text(q.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(vm.selectedId == q.id ? Color.white : Color.primary)
                                .background(
                                    vm.selectedId == q.id ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Shared player surface (inline + fullscreen)

struct LivePlayerSurface: View {
    @ObservedObject var vm: LiveRoomViewModel

    var body: some View {
        ZStack {
            Color.black
            switch vm.playMode {
            case .web:
                if let url = vm.webURL {
                    LiveRoomWebView(url: url)
                } else {
                    Text("无网页地址").foregroundStyle(.white)
                }
            case .native:
                if let url = vm.streamURL {
                    #if canImport(MobileVLCKit)
                    LiveVLCPlayerView(url: url, headers: vm.streamHeaders, isPlaying: true)
                        .id(url.absoluteString)
                    #else
                    if let p = vm.systemPlayer {
                        VideoPlayer(player: p)
                    } else {
                        ProgressView().tint(.white)
                    }
                    #endif
                } else if vm.isLoading {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(vm.statusText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "play.slash")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(vm.errorMessage ?? "暂无画面")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
}

/// True fullscreen player page (not a sheet over the list).
struct LiveRoomFullscreenView: View {
    @ObservedObject var vm: LiveRoomViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showChrome = true

    var body: some View {
        ZStack {
            LivePlayerSurface(vm: vm)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChrome.toggle()
                    }
                }

            if showChrome {
                VStack {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Text(vm.detail?.userName ?? "全屏播放")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        // Balance trailing space with close button.
                        Color.clear.frame(width: 28, height: 28)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer()

                    if vm.playMode == .native, !vm.qualities.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(vm.qualities) { q in
                                    Button {
                                        vm.selectQuality(q)
                                    } label: {
                                        Text(q.name)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .foregroundStyle(vm.selectedId == q.id ? Color.black : Color.white)
                                            .background(
                                                vm.selectedId == q.id ? Color.white : Color.white.opacity(0.2),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 8)
                    }

                    Text(vm.statusText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 20)
                }
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), .clear, Color.black.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                )
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - In-room web player

struct LiveRoomWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        if #available(iOS 15.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = true
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.loaded = url
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loaded != url {
            context.coordinator.loaded = url
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: URL?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let scheme = navigationAction.request.url?.scheme?.lowercased(),
               scheme != "http", scheme != "https", scheme != "about", scheme != "blob" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
