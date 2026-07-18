import SwiftUI
import AVFoundation
import AVKit
import WebKit
import UIKit

// MARK: - Room ViewModel

@MainActor
final class LiveRoomViewModel: ObservableObject {
    enum PlayMode: String, CaseIterable, Identifiable {
        case native = "原生"
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
    @Published private(set) var player: AVPlayer?
    @Published var playMode: PlayMode = .native
    @Published var webURL: URL?

    private var loadTask: Task<Void, Never>?
    private var failWatchTask: Task<Void, Never>?
    /// Keeps resource loader alive for the current item.
    private var headerLoader: LiveHeaderResourceLoader?

    init(room: LiveRoomItem) {
        self.room = room
        webURL = URL(string: defaultWebURL)
    }

    private var defaultWebURL: String {
        switch room.platform {
        case .bilibili: return "https://live.bilibili.com/\(room.roomId)"
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
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        headerLoader = nil
    }

    func retryNative() {
        playMode = .native
        errorMessage = nil
        start()
    }

    func switchToWeb() {
        player?.pause()
        playMode = .web
        statusText = "网页播放"
        isLoading = false
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        statusText = "获取房间信息…"
        defer { isLoading = false }

        do {
            let d = try await LiveSiteRouter.roomDetail(platform: room.platform, roomId: room.roomId)
            guard !Task.isCancelled else { return }
            detail = d
            if let u = URL(string: d.webURL), u.scheme == "http" || u.scheme == "https" {
                webURL = u
            }
            statusText = d.isLive ? "解析播放地址…" : "主播未开播"
            guard d.isLive else {
                errorMessage = "当前未开播"
                // Still allow web page.
                playMode = .web
                return
            }

            let qs = try await LiveSiteRouter.playQualities(detail: d)
            guard !Task.isCancelled else { return }
            qualities = qs
            guard let first = qs.first else {
                errorMessage = "无清晰度，已切换网页播放"
                playMode = .web
                return
            }
            selectedId = first.id
            await play(quality: first)
            // If native still blank shortly after, auto web.
            scheduleAutoWebFallback()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            statusText = "加载失败，切换网页"
            playMode = .web
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

            // HLS only for AVPlayer.
            var candidates = result.urls.filter {
                $0.contains(".m3u8") || $0.contains("/index.m3u8")
            }
            if candidates.isEmpty {
                candidates = result.urls.filter { !$0.contains(".flv") }
            }
            candidates = candidates.filter { URL(string: $0) != nil }

            guard !candidates.isEmpty else {
                errorMessage = "无 HLS 地址（FLV 无法在 iOS 播放）"
                statusText = "改用网页"
                playMode = .web
                return
            }

            var lastErr: String?
            for urlString in candidates.prefix(5) {
                guard let url = URL(string: urlString) else { continue }
                statusText = "连接 \(quality.name)…"
                if await startPlayer(url: url, headers: result.headers) {
                    errorMessage = nil
                    statusText = "播放中 · \(quality.name)"
                    playMode = .native
                    return
                }
                lastErr = "线路不可用"
            }
            errorMessage = (lastErr ?? "播放失败") + "，已切换网页"
            statusText = "网页播放"
            playMode = .web
            player = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            statusText = "拉流失败，网页播放"
            playMode = .web
        }
    }

    private func startPlayer(url: URL, headers: [String: String]) async -> Bool {
        // 1) Direct HTTPS with header options (works when CDN allows).
        if await attachPlayer(
            asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        ) {
            return true
        }
        // 2) Custom-scheme loader injects Referer/Cookie for the playlist request.
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let originalScheme = comps.scheme ?? "https"
        comps.scheme = "livehdr"
        guard let proxyURL = comps.url else { return false }
        let loader = LiveHeaderResourceLoader(headers: headers, realScheme: originalScheme)
        headerLoader = loader
        let asset = AVURLAsset(url: proxyURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return await attachPlayer(asset: asset)
    }

    private func attachPlayer(asset: AVURLAsset) async -> Bool {
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = p
        p.play()
        try? await Task.sleep(nanoseconds: 900_000_000)
        if item.status == .failed {
            player = nil
            return false
        }
        return true
    }

    private func scheduleAutoWebFallback() {
        failWatchTask?.cancel()
        failWatchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.playMode == .native, self.player == nil || self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                // Still no stable playback — fall back.
                if self.player?.timeControlStatus != .playing {
                    self.errorMessage = (self.errorMessage.map { $0 + " · " } ?? "") + "原生无画面，已切网页"
                    self.switchToWeb()
                }
            }
        }
    }
}

// MARK: - Header-injecting resource loader (Referer/Cookie for Bilibili CDN)

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
        // Forward range if any.
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

// MARK: - Room UI

struct LiveRoomView: View {
    let room: LiveRoomItem
    @StateObject private var vm: LiveRoomViewModel
    @ObservedObject private var follows = LiveFollowStore.shared

    init(room: LiveRoomItem) {
        self.room = room
        _vm = StateObject(wrappedValue: LiveRoomViewModel(room: room))
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
                .frame(minHeight: 240, maxHeight: 320)
                .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("模式", selection: $vm.playMode) {
                        ForEach(LiveRoomViewModel.PlayMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.playMode) { _, mode in
                        if mode == .web {
                            vm.player?.pause()
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

                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button("重试原生") { vm.retryNative() }
                            .buttonStyle(.bordered)
                        Button("网页播放") { vm.switchToWeb() }
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
                Button {
                    toggleFollow()
                } label: {
                    Image(systemName: isFollowed ? "star.fill" : "star")
                        .foregroundStyle(isFollowed ? Color.yellow : Color.primary)
                }
            }
        }
        .task { vm.start() }
        .onDisappear { vm.stop() }
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
        ZStack {
            Color.black
            switch vm.playMode {
            case .web:
                if let url = vm.webURL {
                    LiveRoomWebView(url: url)
                } else {
                    Text("无网页地址")
                        .foregroundStyle(.white)
                }
            case .native:
                if let player = vm.player {
                    VideoPlayer(player: player)
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

// MARK: - In-room web player (proven working in 2.4)

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
