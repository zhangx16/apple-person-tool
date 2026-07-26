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
    /// Locks player chrome (no accidental hide/show / quality taps). SimpleLive-style.
    @Published var isControlsLocked = false
    /// Bumps to remount VLC on same URL (decoder restart, SimpleLive Issue #57 style).
    @Published private(set) var streamEpoch: Int = 0

    private var loadTask: Task<Void, Never>?
    private var failWatchTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var warmTask: Task<Void, Never>?
    private var headerLoader: LiveHeaderResourceLoader?
    private var avPlayer: AVPlayer?

    /// CDN candidates for current quality (SimpleLive playUrls + line switch).
    /// Exposed for manual 线路选择 UI.
    @Published private(set) var playCandidates: [URL] = []
    @Published private(set) var playCandidateIndex: Int = 0
    /// "线路1 · xxx.com" labels for chips.
    @Published private(set) var playLineLabels: [String] = []
    private var currentQuality: LivePlayQuality?
    /// Re-open same URL up to 3 times (SimpleLive stream error retry).
    private var streamErrorRetryCount: Int = 0
    /// Re-open / line-switch attempts after decoder restarts exhausted.
    private var mediaErrorRetryCount: Int = 0
    private var lastStreamErrorAt: Date?
    private var isReconnecting = false
    private var playbackGeneration: Int = 0

    /// Exposed for rare AVPlayer fallback (HLS only, no VLC binary).
    var systemPlayer: AVPlayer? { avPlayer }

    init(room: LiveRoomItem) {
        self.room = room
        webURL = URL(string: defaultWebURL)
        // SimpleLive: B站默认应用内拉流（media_kit / VLC）。
        // 清除历史「默认网页」偏好，避免旧崩溃规避逻辑挡住原生播放。
        if room.platform == .bilibili {
            playMode = .native
        } else {
            switch LivePlayPrefs.preferred(for: room.platform) {
            case .web: playMode = .web
            case .native: playMode = .native
            }
        }
    }

    func toggleControlsLock() {
        isControlsLocked.toggle()
    }

    func unlockControls() {
        isControlsLocked = false
    }

    private var defaultWebURL: String {
        switch room.platform {
        // H5 页比桌面站更轻，WKWebView 里更不容易被站点脚本拖垮。
        case .bilibili: return "https://live.bilibili.com/h5/\(room.roomId)"
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
        reconnectTask?.cancel()
        reconnectTask = nil
        warmTask?.cancel()
        warmTask = nil
        isControlsLocked = false
        isReconnecting = false
        clearStream()
    }

    func retryNative() {
        playMode = .native
        LivePlayPrefs.remember(.native, for: room.platform)
        errorMessage = nil
        start()
    }

    /// 用户手动刷新：重拉房间信息 / 线路（应用内）或重载网页。
    func manualRefresh() {
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        streamErrorRetryCount = 0
        mediaErrorRetryCount = 0
        errorMessage = nil
        if playMode == .web {
            //  bump webURL 触发 WKWebView 重载
            if let current = webURL {
                webURL = nil
                DispatchQueue.main.async { [weak self] in
                    self?.webURL = current
                }
            }
            statusText = "刷新网页…"
            start()
        } else {
            statusText = "手动刷新…"
            clearStream()
            start()
        }
    }

    func switchToWeb() {
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        clearStream()
        playMode = .web
        LivePlayPrefs.remember(.web, for: room.platform)
        statusText = "网页播放"
        isLoading = false
        // Still ensure webURL / detail when possible.
        if detail == nil {
            start()
        }
    }

    private func clearStream() {
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
        headerLoader = nil
        streamURL = nil
        streamHeaders = [:]
        streamIsFLV = false
        playCandidates = []
        playCandidateIndex = 0
        playLineLabels = []
        // Session retain/release is owned by LiveVLCPlayerView / LiveRoomWebView lifecycle.
    }

    // MARK: - Playback health (SimpleLive reconnect)

    /// Called by VLC surface when decoder reaches playing.
    func notifyPlayerPlaying() {
        streamErrorRetryCount = 0
        mediaErrorRetryCount = 0
        isReconnecting = false
        lastStreamErrorAt = nil
        if let q = currentQuality, statusText.hasPrefix("重连") || statusText.hasPrefix("切换线路") {
            let linePart = playCandidates.count > 1
                ? " · 线路\(playCandidateIndex + 1)/\(playCandidates.count)"
                : ""
            statusText = "播放中 · \(q.name)" + linePart + (streamIsFLV ? " · FLV" : "")
        }
    }

    /// Called by VLC surface on error / unexpected end — try restart / next line / refresh.
    func notifyPlayerFailed() {
        guard playMode == .native, streamURL != nil else { return }
        guard !isReconnecting else { return }
        let now = Date()
        if let last = lastStreamErrorAt, now.timeIntervalSince(last) < 2 {
            return
        }
        lastStreamErrorAt = now
        isReconnecting = true
        let gen = playbackGeneration
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            // SimpleLive: wait ~1s then reopen decoder / switch line.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, self.playbackGeneration == gen else { return }
            await self.recoverPlayback(generation: gen)
        }
    }

    private func recoverPlayback(generation: Int) async {
        guard playbackGeneration == generation, playMode == .native else {
            isReconnecting = false
            return
        }

        // 1) Re-open same URL (decoder restart) up to 3 times.
        if streamErrorRetryCount < 3, let url = streamURL {
            streamErrorRetryCount += 1
            statusText = "重连中 (\(streamErrorRetryCount)/3)…"
            streamEpoch += 1
            // Force VLC remount even if URL string unchanged.
            streamURL = url
            isReconnecting = false
            return
        }

        // 2) Next CDN line (SimpleLive changePlayLine).
        if playCandidateIndex + 1 < playCandidates.count {
            let nextIndex = playCandidateIndex + 1
            streamErrorRetryCount = 0
            statusText = "切换线路 \(nextIndex + 1)/\(playCandidates.count)…"
            selectPlayLine(nextIndex)
            isReconnecting = false
            return
        }

        // 3) Refresh play URLs for current quality (SimpleLive setPlayer refreshUrls).
        if mediaErrorRetryCount < 2, let q = currentQuality, detail != nil {
            mediaErrorRetryCount += 1
            streamErrorRetryCount = 0
            statusText = "刷新线路 (\(mediaErrorRetryCount)/2)…"
            let ok = await play(quality: q)
            if !ok {
                // try other qualities once
                for other in qualities where other.id != q.id {
                    selectedId = other.id
                    if await play(quality: other) {
                        isReconnecting = false
                        return
                    }
                }
                fallbackToWeb(reason: "断流重试失败，已切网页")
            }
            isReconnecting = false
            return
        }

        statusText = "直播中断"
        errorMessage = "多次重连失败，可刷新或切网页"
        isReconnecting = false
        fallbackToWeb(reason: "长时间断流，已切网页")
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
            // Keep follow list avatar/title fresh when already followed.
            if LiveFollowStore.shared.isFollowing(platform: d.platform, roomId: d.roomId)
                || LiveFollowStore.shared.isFollowing(platform: d.platform, roomId: room.roomId) {
                LiveFollowStore.shared.follow(
                    LiveRoomItem(
                        platform: d.platform,
                        roomId: d.roomId,
                        title: d.title,
                        cover: d.cover,
                        userName: d.userName,
                        online: d.online,
                        userAvatar: d.userAvatar,
                        categoryName: d.categoryName
                    ),
                    isLive: d.isLive
                )
            }

            if playMode == .web {
                statusText = d.isLive ? "网页播放中" : "未开播 · 网页可试"
                LivePlayPrefs.remember(.web, for: room.platform)
                warmTask?.cancel()
                warmTask = Task { [weak self] in await self?.warmQualities(detail: d) }
                return
            }

            statusText = d.isLive ? "解析播放地址…" : "主播未开播"
            guard d.isLive else {
                errorMessage = "当前未开播"
                fallbackToWeb(reason: "未开播，已切网页")
                return
            }

            let qs = try await LiveSiteRouter.playQualities(detail: d)
            guard !Task.isCancelled else { return }
            qualities = qs
            guard let first = qs.first else {
                fallbackToWeb(reason: "无播放线路，已切网页")
                return
            }
            selectedId = first.id
            let ok = await play(quality: first)
            if !ok {
                // Try remaining qualities once, then web.
                var recovered = false
                for q in qs.dropFirst().prefix(3) {
                    selectedId = q.id
                    if await play(quality: q) {
                        recovered = true
                        break
                    }
                }
                if !recovered {
                    fallbackToWeb(reason: "拉流失败，已自动切网页")
                    return
                }
            }
            LivePlayPrefs.remember(.native, for: room.platform)
            scheduleAutoWebFallback()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let msg = error.localizedDescription
            if room.platform == .douyin, msg.contains("Cookie") || msg.contains("风控") || msg.contains("登录") {
                errorMessage = msg + " · 可在设置配置抖音直播 Cookie"
            } else if room.platform == .bilibili,
                      msg.contains("Cookie") || msg.contains("登录") || msg.contains("-352")
                        || msg.contains("风控") || msg.contains("未获取到") {
                errorMessage = msg + " · 可在设置配置 B站 Cookie（SESSDATA）"
            } else {
                errorMessage = msg
            }
            fallbackToWeb(reason: "加载失败，已切网页")
        }
    }

    private func fallbackToWeb(reason: String) {
        clearStream()
        playMode = .web
        statusText = reason
        LivePlayPrefs.remember(.web, for: room.platform)
    }

    private func mobileWebURL(for d: LiveRoomDetail) -> String {
        switch d.platform {
        case .bilibili: return "https://live.bilibili.com/h5/\(d.roomId)"
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
        streamErrorRetryCount = 0
        mediaErrorRetryCount = 0
        isReconnecting = false
        reconnectTask?.cancel()
        Task { await play(quality: q) }
    }

    /// Manual CDN line switch (SimpleLive `changePlayLine`).
    func selectPlayLine(_ index: Int) {
        guard playMode == .native else { return }
        guard playCandidates.indices.contains(index) else { return }
        guard index != playCandidateIndex || streamURL != playCandidates[index] else { return }

        playCandidateIndex = index
        streamErrorRetryCount = 0
        mediaErrorRetryCount = 0
        isReconnecting = false
        reconnectTask?.cancel()
        playbackGeneration += 1

        let next = playCandidates[index]
        let isFLV = next.absoluteString.lowercased().contains(".flv")
        let isHLS = next.absoluteString.lowercased().contains(".m3u8")
        streamIsFLV = isFLV
        streamEpoch += 1
        streamURL = next
        errorMessage = nil
        let qName = currentQuality?.name ?? "清晰度"
        statusText = "播放中 · \(qName) · 线路\(index + 1)/\(playCandidates.count)"
            + (isFLV ? " · FLV" : (isHLS ? " · HLS" : ""))

        #if !canImport(MobileVLCKit)
        // AVPlayer path: remount item on selected URL.
        if !isFLV {
            Task {
                _ = await startAVPlayer(url: next, headers: streamHeaders)
            }
        }
        #endif
    }

    var currentLineInfo: String {
        guard !playCandidates.isEmpty else { return "无线路" }
        let i = min(max(playCandidateIndex, 0), playCandidates.count - 1)
        if playLineLabels.indices.contains(i) {
            return playLineLabels[i]
        }
        return "线路\(i + 1)/\(playCandidates.count)"
    }

    private static func lineLabels(for urls: [URL]) -> [String] {
        urls.enumerated().map { idx, url in
            let host = url.host ?? "线路"
            // Shorten host for chips: cdn.example.com → example.com / last 2 labels
            let parts = host.split(separator: ".")
            let short: String = {
                if parts.count >= 2 {
                    return parts.suffix(2).joined(separator: ".")
                }
                return host
            }()
            let kind: String = {
                let s = url.absoluteString.lowercased()
                if s.contains(".flv") { return "FLV" }
                if s.contains(".m3u8") { return "HLS" }
                return ""
            }()
            if kind.isEmpty {
                return "线路\(idx + 1) · \(short)"
            }
            return "线路\(idx + 1) · \(short) · \(kind)"
        }
    }

    @discardableResult
    private func play(quality: LivePlayQuality) async -> Bool {
        guard let detail else { return false }
        currentQuality = quality
        statusText = "拉取线路 \(quality.name)…"
        do {
            let result = try await LiveSiteRouter.playURLs(detail: detail, quality: quality)
            guard !Task.isCancelled else { return false }

            // SimpleLive: mcdn last; keep original order otherwise (FLV primary for live).
            let ordered = Self.rankURLs(result.urls)
            guard !ordered.isEmpty else {
                errorMessage = nil
                statusText = "无可用地址"
                return false
            }

            var urls: [URL] = []
            for urlString in ordered.prefix(8) {
                let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmedURL),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { continue }
                urls.append(url)
            }
            guard let first = urls.first else {
                statusText = "线路均不可用"
                return false
            }

            let headers = result.headers.mapValues { v in
                v.replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\n", with: " ")
            }
            let isFLV = first.absoluteString.lowercased().contains(".flv")
            let isHLS = first.absoluteString.lowercased().contains(".m3u8")

            #if canImport(MobileVLCKit)
            // Keep AVPlayer cleared; attach all candidates for line-switch reconnect.
            avPlayer?.pause()
            avPlayer?.replaceCurrentItem(with: nil)
            avPlayer = nil
            headerLoader = nil
            playCandidates = urls
            playCandidateIndex = 0
            playLineLabels = Self.lineLabels(for: urls)
            streamErrorRetryCount = 0
            playbackGeneration += 1
            streamHeaders = headers
            streamIsFLV = isFLV
            streamEpoch += 1
            streamURL = first
            playMode = .native
            errorMessage = nil
            statusText = "播放中 · \(quality.name) · 线路1/\(urls.count)"
                + (isFLV ? " · FLV" : (isHLS ? " · HLS" : ""))
            return true
            #else
            if isFLV {
                // Without VLC, try first non-FLV.
                for url in urls where !url.absoluteString.lowercased().contains(".flv") {
                    if await startAVPlayer(url: url, headers: headers) {
                        playCandidates = urls
                        playCandidateIndex = urls.firstIndex(of: url) ?? 0
                        playLineLabels = Self.lineLabels(for: urls)
                        streamIsFLV = false
                        streamURL = url
                        streamHeaders = headers
                        playMode = .native
                        errorMessage = nil
                        statusText = "播放中 · \(quality.name) · \(currentLineInfo)"
                        return true
                    }
                }
                statusText = "线路均不可用"
                return false
            }
            if await startAVPlayer(url: first, headers: headers) {
                playCandidates = urls
                playCandidateIndex = 0
                playLineLabels = Self.lineLabels(for: urls)
                streamIsFLV = false
                streamURL = first
                streamHeaders = headers
                playMode = .native
                errorMessage = nil
                statusText = "播放中 · \(quality.name) · 线路1/\(urls.count)"
                return true
            }
            statusText = "线路均不可用"
            return false
            #endif
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = error.localizedDescription
            statusText = "拉流失败"
            return false
        }
    }

    private static func rankURLs(_ urls: [String]) -> [String] {
        // Align SimpleLive: demote mcdn only; keep FLV/HLS order from site.
        urls
            .filter { URL(string: $0) != nil }
            .sorted { a, b in
                let amd = a.contains("mcdn")
                let bmd = b.contains("mcdn")
                if amd != bmd { return !amd && bmd }
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
        // AVPlayer path has no UIViewRepresentable retain pair; just pin category.
        LiveAudioSession.reassertCategory()
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
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.playMode == .native, self.streamURL == nil {
                self.fallbackToWeb(reason: "长时间无画面，已自动切网页")
            }
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

// MARK: - Room UI (mainstream live layout: player chrome + anchor card)

struct LiveRoomView: View {
    let room: LiveRoomItem
    @StateObject private var vm: LiveRoomViewModel
    @StateObject private var danmaku = LiveDanmakuService()
    @ObservedObject private var follows = LiveFollowStore.shared
    @State private var isPlayerFullscreen = false
    @State private var showPlayerChrome = true
    @State private var showDanmaku = LiveDanmakuPrefs.shared.enabled
    @State private var showDanmakuSettings = false

    init(room: LiveRoomItem) {
        self.room = room
        _vm = StateObject(wrappedValue: LiveRoomViewModel(room: room))
    }

    private var platform: LivePlatform { vm.detail?.platform ?? room.platform }
    private var brand: Color { LiveUI.brand(platform) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                playerHero
                VStack(spacing: 12) {
                    anchorCard
                    titleBlock
                    danmakuSection
                    if vm.playMode == .native {
                        qualitySection
                        // 线路：自动切换（卡顿/断流时 ViewModel 自动换 CDN），不展示手动选线。
                    }
                    engineSection
                    if let err = vm.errorMessage, !err.isEmpty {
                        errorBanner(err)
                    }
                    tipsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background {
            ZStack {
                Color(.systemGroupedBackground)
                LinearGradient(
                    colors: [brand.opacity(0.07), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    LiveUI.liveDot(isLive: vm.detail?.isLive == true)
                    Text(shortTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            // 顶部右侧：手动刷新（全屏已在播放器控件内，不再重复）
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showDanmaku.toggle()
                        danmaku.isEnabled = showDanmaku
                        LiveDanmakuPrefs.shared.enabled = showDanmaku
                        if showDanmaku {
                            restartDanmakuIfNeeded()
                        } else {
                            danmaku.stop()
                        }
                    } label: {
                        Image(systemName: showDanmaku ? "text.bubble.fill" : "text.bubble")
                    }
                    .accessibilityLabel(showDanmaku ? "关闭弹幕" : "开启弹幕")

                    Button {
                        showDanmakuSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("弹幕设置")

                    Button {
                        vm.manualRefresh()
                        restartDanmakuIfNeeded()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新直播")
                }
            }
        }
        .sheet(isPresented: $showDanmakuSettings) {
            LiveDanmakuSettingsSheet()
        }
        .task { vm.start() }
        .onChange(of: vm.detail?.danmakuJSON) { _, _ in
            restartDanmakuIfNeeded()
        }
        .onChange(of: vm.detail?.roomId) { _, _ in
            restartDanmakuIfNeeded()
        }
        .onDisappear {
            // fullScreenCover 可能触发父视图 disappear；全屏时保持播放与弹幕。
            if !isPlayerFullscreen {
                danmaku.stop()
                vm.stop()
            }
        }
        .fullScreenCover(isPresented: $isPlayerFullscreen) {
            LiveRoomFullscreenView(vm: vm, danmaku: danmaku, showDanmaku: $showDanmaku)
        }
        .onChange(of: isPlayerFullscreen) { _, fullscreen in
            if fullscreen {
                OrientationHelper.lockLandscape()
            } else {
                OrientationHelper.lockPortrait()
            }
        }
    }

    private func restartDanmakuIfNeeded() {
        guard showDanmaku else { return }
        guard let detail = vm.detail else { return }
        danmaku.isEnabled = true
        danmaku.start(
            platform: detail.platform,
            danmakuJSON: detail.danmakuJSON,
            roomId: detail.roomId
        )
    }

    private var shortTitle: String {
        let n = vm.detail?.userName ?? room.userName
        return n.isEmpty ? "直播间" : n
    }

    // MARK: Player (16:9, overlays like 虎牙/斗鱼/B站)

    private var playerHero: some View {
        GeometryReader { geo in
            ZStack {
                // Tear down decoder while fullscreen so we never run two streams at once.
                LivePlayerSurface(vm: vm, isActive: !isPlayerFullscreen)

                // Floating danmaku on the video surface (portrait: bottom stack)
                if showDanmaku, !isPlayerFullscreen {
                    LiveDanmakuOverlay(messages: danmaku.messages, placement: .bottomStack)
                        .allowsHitTesting(false)
                }

                // Locked: only side unlock (ignore other taps on chrome).
                if vm.isControlsLocked {
                    lockOnlyOverlay(compact: true)
                } else if showPlayerChrome {
                    playerOverlay
                }
            }
            .frame(width: geo.size.width, height: geo.size.width * 9 / 16)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                guard !vm.isControlsLocked else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    showPlayerChrome.toggle()
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.black)
    }

    /// Side lock / unlock control (SimpleLive-style).
    private func lockOnlyOverlay(compact: Bool) -> some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vm.unlockControls()
                    showPlayerChrome = true
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
                    if !compact {
                        Text("解锁")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: compact ? 40 : 48, height: compact ? 40 : 56)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("解锁控件")
            .padding(.trailing, compact ? 10 : 16)
        }
    }

    private var playerOverlay: some View {
        ZStack {
            // Top / bottom scrims
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 72)
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 88)
            }
            .allowsHitTesting(false)

            VStack {
                HStack(spacing: 8) {
                    LiveUI.liveBadge(isLive: vm.detail?.isLive == true)
                    LiveUI.platformChip(platform)
                    Spacer()
                    Text(vm.statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.35), in: Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer()

                HStack(spacing: 10) {
                    // Engine mini toggle
                    Menu {
                        Button {
                            vm.retryNative()
                        } label: {
                            Label("应用内播放", systemImage: "play.rectangle.fill")
                        }
                        Button {
                            vm.switchToWeb()
                        } label: {
                            Label("网页播放", systemImage: "safari")
                        }
                        if vm.playMode == .native {
                            Button {
                                vm.retryNative()
                            } label: {
                                Label("重新拉流", systemImage: "arrow.clockwise")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: vm.playMode == .native ? "play.rectangle.fill" : "safari")
                            Text(vm.playMode.rawValue)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.18), in: Capsule())
                    }

                    if vm.playMode == .native, let name = selectedQualityName {
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.18), in: Capsule())
                    }

                    Spacer()

                    // Manual refresh on the player chrome
                    Button {
                        vm.manualRefresh()
                        restartDanmakuIfNeeded()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新")

                    // Lock controls
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.isControlsLocked = true
                            showPlayerChrome = false
                        }
                    } label: {
                        Image(systemName: "lock.open")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("锁定控件")

                    Button {
                        isPlayerFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("全屏")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private var selectedQualityName: String? {
        guard let id = vm.selectedId else { return vm.qualities.first?.name }
        return vm.qualities.first(where: { $0.id == id })?.name
    }

    // MARK: Anchor card (avatar · name · follow)

    private var anchorCard: some View {
        HStack(spacing: 12) {
            avatarView
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    LivePlatformMark(platform: platform, size: 14)
                    Text(platform.title)
                    Text("·")
                    Text("房间 \(vm.detail?.roomId ?? room.roomId)")
                    if let online = displayOnline {
                        Text("·")
                        Label(online, systemImage: "person.2.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                toggleFollow()
            } label: {
                Text(isFollowed ? "已关注" : "+ 关注")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFollowed ? Color.primary : Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background {
                        if isFollowed {
                            Capsule().fill(Color(.tertiarySystemFill))
                        } else {
                            Capsule().fill(brand.brandGradient)
                        }
                    }
                    .overlay {
                        if !isFollowed {
                            Capsule()
                                .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                        }
                    }
                    .shadow(color: isFollowed ? .clear : brand.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .appCardV2(corner: 20, padding: 16)
    }

    private var avatarView: some View {
        let cover = vm.detail?.userAvatar.isEmpty == false ? (vm.detail?.userAvatar ?? "") : (vm.detail?.cover ?? room.cover)
        return ZStack {
            Circle().fill(brand.opacity(0.2))
            if let url = URL(string: cover), url.scheme == "http" || url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .foregroundStyle(brand)
                    }
                }
            } else {
                Image(systemName: "person.fill")
                    .foregroundStyle(brand)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .overlay(Circle().stroke(brand.opacity(0.35), lineWidth: 1.5))
    }

    private var displayName: String {
        let n = vm.detail?.userName ?? room.userName
        return n.isEmpty ? "主播 \(vm.detail?.roomId ?? room.roomId)" : n
    }

    private var displayOnline: String? {
        let n = vm.detail?.online ?? room.online
        guard n > 0 else { return nil }
        return LiveUI.formatCount(n)
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.detail?.title ?? (room.title.isEmpty ? "直播间 \(room.roomId)" : room.title))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let intro = vm.detail?.introduction, !intro.isEmpty {
                Text(intro)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardV2(corner: 20, padding: 16)
    }

    // MARK: Quality

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("清晰度")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(vm.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if vm.qualities.isEmpty {
                Text(vm.isLoading ? "线路解析中…" : "暂无清晰度（可切网页）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.qualities) { q in
                            let on = vm.selectedId == q.id
                            Button {
                                vm.selectQuality(q)
                            } label: {
                                Text(q.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background {
                                        if on {
                                            Capsule().fill(brand.brandGradient)
                                        } else {
                                            Capsule().fill(Color(.tertiarySystemFill))
                                        }
                                    }
                                    .overlay {
                                        if on {
                                            Capsule()
                                                .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                                        }
                                    }
                                    .shadow(color: on ? brand.opacity(0.3) : .clear, radius: 6, y: 2)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
            }
        }
        .appCardV2(corner: 20, padding: 16)
    }

    /// CDN / play URL lines for current quality (SimpleLive 线路选择).
    @ViewBuilder
    private var playLineSection: some View {
        if vm.playMode == .native, !vm.playCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("线路")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(vm.currentLineInfo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vm.playCandidates.enumerated()), id: \.offset) { index, _ in
                            let on = index == vm.playCandidateIndex
                            let title = vm.playLineLabels.indices.contains(index)
                                ? vm.playLineLabels[index]
                                : "线路\(index + 1)"
                            Button {
                                vm.selectPlayLine(index)
                            } label: {
                                Text(title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background {
                                        if on {
                                            Capsule().fill(brand.brandGradient)
                                        } else {
                                            Capsule().fill(Color(.tertiarySystemFill))
                                        }
                                    }
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel(title)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                Text("同一清晰度下的多 CDN 节点；卡顿可手动换线（与 Simple Live 一致）。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .appCardV2(corner: 20, padding: 16)
        }
    }

    // MARK: Engine

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放方式")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                engineButton(
                    title: "应用内",
                    subtitle: room.platform == .bilibili ? "VLC · FLV/HLS" : "VLC · FLV",
                    icon: "play.rectangle.fill",
                    selected: vm.playMode == .native
                ) {
                    vm.retryNative()
                }
                engineButton(
                    title: "网页",
                    subtitle: "站点页面",
                    icon: "safari",
                    selected: vm.playMode == .web
                ) {
                    vm.switchToWeb()
                }
            }
            Button {
                vm.manualRefresh()
                restartDanmakuIfNeeded()
            } label: {
                Label("刷新直播", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(brand.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                    }
                    .shadow(color: brand.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .appCardV2(corner: 20, padding: 16)
    }

    // MARK: Danmaku panel

    private var danmakuSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("弹幕", systemImage: "text.bubble")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !danmaku.statusText.isEmpty {
                    Text(danmaku.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    showDanmakuSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("弹幕设置")

                Toggle("", isOn: Binding(
                    get: { showDanmaku },
                    set: { on in
                        showDanmaku = on
                        danmaku.isEnabled = on
                        LiveDanmakuPrefs.shared.enabled = on
                        if on {
                            restartDanmakuIfNeeded()
                        } else {
                            danmaku.stop()
                        }
                    }
                ))
                .labelsHidden()
                .tint(brand)
                .controlSize(.mini)
            }

            if !showDanmaku {
                Text("弹幕已关闭 · 可点右侧滑杆打开设置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if panelMessages.isEmpty {
                Text(danmaku.statusText.isEmpty ? "等待弹幕…" : danmaku.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(panelMessages.suffix(40)) { msg in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(msg.userName.isEmpty ? "用户" : msg.userName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(brand.opacity(0.9))
                                        .lineLimit(1)
                                    Text(msg.text)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(msg.id)
                                .contextMenu {
                                    if !msg.userName.isEmpty {
                                        Button {
                                            LiveDanmakuPrefs.shared.addBlockUser(msg.userName)
                                        } label: {
                                            Label("屏蔽用户 \(msg.userName)", systemImage: "person.crop.circle.badge.xmark")
                                        }
                                    }
                                    Button {
                                        LiveDanmakuPrefs.shared.addBlockWord(msg.text)
                                    } label: {
                                        Label("屏蔽此句关键词", systemImage: "text.badge.xmark")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                    .onChange(of: danmaku.messages.count) { _, _ in
                        if let last = panelMessages.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .appCardV2(corner: 20, padding: 16)
    }

    private var panelMessages: [LiveChatMessage] {
        let prefs = LiveDanmakuPrefs.shared
        return danmaku.messages.filter { prefs.allows(userName: $0.userName, text: $0.text) }
    }

    private func engineButton(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selected ? brand : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(brand)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? brand.opacity(0.55) : Color(.separator).opacity(0.35), lineWidth: selected ? 1.5 : 1)
                    .background(
                        (selected ? brand.opacity(0.08) : Color(.tertiarySystemFill).opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tipsCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow.opacity(0.9))
            Text("点播放器显示控件；右上角可刷新/开关弹幕；锁图标防误触；全屏在播放器内。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            online: vm.detail?.online ?? room.online,
            userAvatar: vm.detail?.userAvatar ?? room.userAvatar,
            categoryName: vm.detail?.categoryName ?? room.categoryName
        )
        if isFollowed {
            follows.unfollow(platform: item.platform, roomId: item.roomId)
        } else {
            follows.follow(item)
        }
    }
}

// MARK: - UI helpers

enum LiveUI {
    static func brand(_ p: LivePlatform) -> Color {
        switch p {
        case .bilibili: return Color(red: 0.0, green: 0.63, blue: 0.84) // #00A1D6
        case .huya: return Color(red: 1.0, green: 0.55, blue: 0.0)
        case .douyu: return Color(red: 1.0, green: 0.42, blue: 0.0)
        case .douyin: return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .kuaishou: return Color(red: 1.0, green: 0.29, blue: 0.02)
        }
    }

    static func formatCount(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 100_000_000) }
        if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
        return "\(n)"
    }

    static func liveDot(isLive: Bool) -> some View {
        Circle()
            .fill(isLive ? Color.red : Color.secondary)
            .frame(width: 8, height: 8)
    }

    static func liveBadge(isLive: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
            Text(isLive ? "LIVE" : "OFF")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isLive ? Color.red : Color.gray, in: Capsule())
    }

    static func platformChip(_ p: LivePlatform) -> some View {
        HStack(spacing: 4) {
            LivePlatformMark(platform: p, size: 14)
            Text(p.title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.35), in: Capsule())
    }
}

/// Official app-style brand mark (asset catalog) with SF Symbol fallback.
struct LivePlatformMark: View {
    let platform: LivePlatform
    var size: CGFloat = 20

    var body: some View {
        Group {
            if UIImage(named: platform.brandAssetName) != nil {
                Image(platform.brandAssetName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(LiveUI.brand(platform))
                    Image(systemName: platform.systemImage)
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}

// MARK: - Danmaku floating overlay (on video)

struct LiveDanmakuOverlay: View {
    enum Placement {
        /// 竖屏播放器底部堆叠
        case bottomStack
        /// 全屏主流弹幕：横向滚动（右→左，B站/斗鱼风格）
        case flying
    }

    let messages: [LiveChatMessage]
    var placement: Placement = .bottomStack
    @ObservedObject private var prefs = LiveDanmakuPrefs.shared

    private var filtered: [LiveChatMessage] {
        messages.filter { prefs.allows(userName: $0.userName, text: $0.text) }
    }

    private var visible: [LiveChatMessage] {
        switch placement {
        case .bottomStack: return Array(filtered.suffix(6))
        case .flying: return Array(filtered.suffix(40))
        }
    }

    var body: some View {
        Group {
            switch placement {
            case .bottomStack:
                bottomStackBody
            case .flying:
                flyingBody
            }
        }
        .opacity(prefs.enabled ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var bottomStackBody: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(visible) { msg in
                    danmakuChip(msg, compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .opacity(prefs.opacity)
            .animation(.easeOut(duration: 0.2), value: messages.count)
        }
    }

    /// 主流：弹幕从右侧进入、向左飞出；范围/位置/字号/透明度/速度可调。
    private var flyingBody: some View {
        GeometryReader { geo in
            let areaH = geo.size.height * prefs.areaRatio
            let trackCount = prefs.resolvedTrackCount(containerHeight: geo.size.height)
            let trackH = areaH / CGFloat(max(trackCount, 1))
            let bandAlign: Alignment = {
                switch prefs.verticalAlign {
                case .top: return .top
                case .center: return .center
                case .bottom: return .bottom
                }
            }()

            ZStack(alignment: .top) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { idx, msg in
                    FlyingDanmakuLine(
                        text: displayText(msg),
                        color: Color(hexColor: msg.colorHex),
                        fontSize: prefs.fontSize,
                        opacity: prefs.opacity,
                        strokeEnabled: prefs.strokeEnabled,
                        track: idx % max(trackCount, 1),
                        trackHeight: trackH,
                        containerWidth: geo.size.width,
                        duration: prefs.speedDuration + Double(idx % 4) * 0.25
                    )
                }
            }
            .frame(height: areaH, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bandAlign)
            .clipped()
        }
    }

    private func displayText(_ msg: LiveChatMessage) -> String {
        if prefs.showUsername, !msg.userName.isEmpty {
            return "\(msg.userName)：\(msg.text)"
        }
        return msg.text
    }

    private func danmakuChip(_ msg: LiveChatMessage, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if prefs.showUsername {
                Text(msg.userName.isEmpty ? "用户" : msg.userName)
                    .font(.system(size: max(10, prefs.fontSize - 3), weight: .bold))
                    .foregroundStyle(Color(hexColor: msg.colorHex))
            }
            Text(msg.text)
                .font(.system(size: max(11, prefs.fontSize - 2), weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(compact ? 1 : 2)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(Color.black.opacity(compact ? 0.42 : 0.48), in: Capsule())
    }
}

/// Single flying bullet (right → left).
private struct FlyingDanmakuLine: View {
    let text: String
    let color: Color
    let fontSize: Double
    let opacity: Double
    let strokeEnabled: Bool
    let track: Int
    let trackHeight: CGFloat
    let containerWidth: CGFloat
    let duration: Double

    @State private var x: CGFloat = 0
    @State private var started = false

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(color.opacity(opacity))
            .shadow(
                color: strokeEnabled ? .black.opacity(0.65) : .clear,
                radius: strokeEnabled ? 1.2 : 0,
                y: strokeEnabled ? 1 : 0
            )
            .lineLimit(1)
            .fixedSize()
            .offset(x: x, y: CGFloat(track) * trackHeight + 4)
            .onAppear {
                guard !started else { return }
                started = true
                x = containerWidth + 20
                withAnimation(.linear(duration: max(3.5, duration))) {
                    x = -containerWidth - 240
                }
            }
    }
}

/// Settings panel for live danmaku (参考 simple_live 弹幕设置结构).
struct LiveDanmakuSettingsSheet: View {
    @ObservedObject private var prefs = LiveDanmakuPrefs.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newBlockWord = ""
    @State private var newBlockUser = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("显示弹幕", isOn: $prefs.enabled)
                    Toggle("启用屏蔽", isOn: $prefs.shieldEnabled)
                } header: {
                    Text("总开关")
                } footer: {
                    Text("关闭「启用屏蔽」后，关键词与用户屏蔽均暂时失效。")
                }

                Section("显示位置与区域") {
                    Picker("弹幕位置", selection: $prefs.verticalAlign) {
                        ForEach(LiveDanmakuVerticalAlign.allCases) { align in
                            Label(align.title, systemImage: align.systemImage).tag(align)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("显示区域")
                        Slider(value: $prefs.areaRatio, in: 0.15...1.0, step: 0.05)
                        Text("\(Int(prefs.areaRatio * 100))%")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    Text("区域 = 画面高度占比；位置决定该区域贴顶/居中/贴底（全屏飞幕）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("轨道行数")
                        Slider(
                            value: Binding(
                                get: { Double(prefs.maxTracks) },
                                set: { prefs.maxTracks = Int($0) }
                            ),
                            in: 0...14,
                            step: 1
                        )
                        Text(prefs.maxTracks == 0 ? "自动" : "\(prefs.maxTracks)")
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                }

                Section("外观") {
                    HStack {
                        Text("字号")
                        Slider(value: $prefs.fontSize, in: 10...28, step: 1)
                        Text("\(Int(prefs.fontSize))")
                            .monospacedDigit()
                            .frame(width: 28)
                    }
                    HStack {
                        Text("透明度")
                        Slider(value: $prefs.opacity, in: 0.15...1.0, step: 0.05)
                        Text("\(Int(prefs.opacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    HStack {
                        Text("滚动速度")
                        Slider(value: $prefs.speedDuration, in: 4...16, step: 0.5)
                        Text("\(String(format: "%.0f", prefs.speedDuration))s")
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                    Text("数值为飞过屏幕大致秒数，越小越快（同 simple_live）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Toggle("显示用户名", isOn: $prefs.showUsername)
                    Toggle("描边阴影", isOn: $prefs.strokeEnabled)
                }

                Section {
                    HStack {
                        TextField("添加屏蔽词", text: $newBlockWord)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("添加") {
                            prefs.addBlockWord(newBlockWord)
                            newBlockWord = ""
                        }
                        .disabled(newBlockWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if prefs.blockWords.isEmpty {
                        Text("暂无屏蔽词。命中则整条弹幕不显示。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowChipList(items: prefs.blockWords) { word in
                            prefs.removeBlockWord(word)
                        }
                    }
                    TextField("批量编辑（逗号/换行分隔）", text: $prefs.blockWordsRaw, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.caption)
                } header: {
                    Text("关键词屏蔽")
                }

                Section {
                    HStack {
                        TextField("添加屏蔽用户", text: $newBlockUser)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("添加") {
                            prefs.addBlockUser(newBlockUser)
                            newBlockUser = ""
                        }
                        .disabled(newBlockUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if prefs.blockUsers.isEmpty {
                        Text("暂无屏蔽用户。用户名包含关键词即过滤。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowChipList(items: prefs.blockUsers) { name in
                            prefs.removeBlockUser(name)
                        }
                    }
                    TextField("批量编辑（逗号/换行分隔）", text: $prefs.blockUsersRaw, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.caption)
                } header: {
                    Text("用户屏蔽")
                }

                Section {
                    Text("全屏为横向飞幕；竖屏播放器为底部堆叠，同样应用透明度/字号/屏蔽规则。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Simple wrap chips for shield lists.
private struct FlowChipList: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlexibleChipWrap(items: items, onRemove: onRemove)
    }
}

private struct FlexibleChipWrap: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        // Simple multi-line HStack rows without extra layout deps.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunked(items, size: 3), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Button {
                            onRemove(item)
                        } label: {
                            HStack(spacing: 4) {
                                Text(item)
                                    .font(.caption)
                                    .lineLimit(1)
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ list: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [list] }
        var result: [[String]] = []
        var i = 0
        while i < list.count {
            let end = min(i + size, list.count)
            result.append(Array(list[i..<end]))
            i = end
        }
        return result
    }
}

private extension Color {
    init(hexColor: UInt32) {
        let r = Double((hexColor >> 16) & 0xFF) / 255.0
        let g = Double((hexColor >> 8) & 0xFF) / 255.0
        let b = Double(hexColor & 0xFF) / 255.0
        // Near-white defaults → soft cyan so names stay readable on video.
        if r > 0.9, g > 0.9, b > 0.9 {
            self = Color(red: 0.55, green: 0.85, blue: 1.0)
        } else {
            self = Color(red: r, green: g, blue: b)
        }
    }
}

// MARK: - Shared player surface (inline + fullscreen)

struct LivePlayerSurface: View {
    @ObservedObject var vm: LiveRoomViewModel
    /// Only one surface may mount a decoder at a time.
    /// Inline + fullscreen both observing the same VM used to create two VLC/Web
    /// players → delayed double audio (very obvious on headphones).
    var isActive: Bool = true

    var body: some View {
        ZStack {
            Color.black
            if isActive {
                activeContent
            }
            // When inactive (covered by fullscreen), keep black chrome only — no second audio path.
        }
    }

    @ViewBuilder
    private var activeContent: some View {
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
                // Prefer AVPlayer when the VM already attached one (HLS fallback).
                // Otherwise VLC (SimpleLive media_kit role) for FLV/HLS.
                if let p = vm.systemPlayer {
                    VideoPlayer(player: p)
                        .id(url.absoluteString + "-av-\(vm.streamEpoch)")
                } else {
                    LiveVLCPlayerView(
                        url: url,
                        headers: vm.streamHeaders,
                        isPlaying: true,
                        onPlaybackFailed: { vm.notifyPlayerFailed() },
                        onPlaying: { vm.notifyPlayerPlaying() }
                    )
                    .id(url.absoluteString + "-vlc-\(vm.streamEpoch)")
                }
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

/// Fullscreen player — SimpleLive 风格：竖滑亮度/音量、锁定可隐藏、控制条
struct LiveRoomFullscreenView: View {
    @ObservedObject var vm: LiveRoomViewModel
    @ObservedObject var danmaku: LiveDanmakuService
    @Binding var showDanmaku: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showChrome = true
    /// 锁定时解锁条默认隐藏，点击画面再显示（避免挡画面）。
    @State private var showLockChrome = false
    @State private var gestureTip: String?
    @State private var gestureBaseBrightness: CGFloat = 0.5
    @State private var gestureBaseVolume: Float = 0.5
    @State private var gestureIsLeft = true
    @State private var gestureActive = false
    @State private var lockChromeHideTask: Task<Void, Never>?
    @State private var showDanmakuSettings = false

    private var brand: Color {
        LiveUI.brand(vm.detail?.platform ?? .huya)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LivePlayerSurface(vm: vm, isActive: true)
                    .ignoresSafeArea()

                // 全屏主流弹幕：横向飞幕
                if showDanmaku {
                    LiveDanmakuOverlay(messages: danmaku.messages, placement: .flying)
                        .allowsHitTesting(false)
                        .padding(.top, 48)
                }

                // Full-screen hit layer: tap + vertical drag (brightness/volume).
                // Placed under chrome so buttons still receive hits.
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(fullscreenDragGesture(size: geo.size))
                    .onTapGesture {
                        handleSurfaceTap()
                    }

                if vm.isControlsLocked {
                    if showLockChrome {
                        HStack {
                            unlockSideButton
                            Spacer()
                            unlockSideButton
                        }
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                    }
                } else if showChrome {
                    fullscreenChrome
                }

                if let gestureTip {
                    Text(gestureTip)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            OrientationHelper.lockLandscape()
        }
        .onDisappear {
            lockChromeHideTask?.cancel()
            OrientationHelper.lockPortrait()
        }
        .onChange(of: vm.isControlsLocked) { _, locked in
            if locked {
                showChrome = false
                showLockChrome = false
            } else {
                showLockChrome = false
                showChrome = true
            }
        }
    }

    private var fullscreenChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        LiveUI.liveBadge(isLive: vm.detail?.isLive == true)
                        Text(vm.detail?.userName ?? "直播")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Text(vm.detail?.title ?? "")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    vm.manualRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("刷新直播")
                Button {
                    showDanmaku.toggle()
                    danmaku.isEnabled = showDanmaku
                    LiveDanmakuPrefs.shared.enabled = showDanmaku
                    if showDanmaku, let detail = vm.detail {
                        danmaku.start(
                            platform: detail.platform,
                            danmakuJSON: detail.danmakuJSON,
                            roomId: detail.roomId
                        )
                    } else if !showDanmaku {
                        danmaku.stop()
                    }
                } label: {
                    Image(systemName: showDanmaku ? "text.bubble.fill" : "text.bubble")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel(showDanmaku ? "关闭弹幕" : "开启弹幕")
                Button {
                    showDanmakuSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("弹幕设置")
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vm.isControlsLocked = true
                        showChrome = false
                        showLockChrome = false
                    }
                } label: {
                    Image(systemName: "lock.open")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("锁定控件")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .sheet(isPresented: $showDanmakuSettings) {
                LiveDanmakuSettingsSheet()
            }

            Spacer()

            if vm.playMode == .native, !vm.qualities.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.qualities) { q in
                            let on = vm.selectedId == q.id
                            Button { vm.selectQuality(q) } label: {
                                Text(q.name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(on ? Color.black : Color.white)
                                    .background(on ? Color.white : Color.white.opacity(0.2), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }

            // 线路自动切换（卡顿 → 下一 CDN），全屏不再提供手动选线芯片。

            HStack {
                Text(vm.statusText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
                Button {
                    if vm.playMode == .native { vm.switchToWeb() }
                    else { vm.retryNative() }
                } label: {
                    Text(vm.playMode == .native ? "切网页" : "切应用内")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(brand.opacity(0.9), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), .clear, Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var unlockSideButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                vm.unlockControls()
                showChrome = true
                showLockChrome = false
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.title3.weight(.semibold))
                Text("解锁")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 52, height: 64)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("解锁控件")
    }

    // MARK: - Gestures (SimpleLive: left brightness / right volume)

    private func handleSurfaceTap() {
        if vm.isControlsLocked {
            withAnimation(.easeInOut(duration: 0.2)) {
                showLockChrome.toggle()
            }
            if showLockChrome {
                scheduleHideLockChrome()
            } else {
                lockChromeHideTask?.cancel()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                showChrome.toggle()
            }
        }
    }

    private func scheduleHideLockChrome() {
        lockChromeHideTask?.cancel()
        lockChromeHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLockChrome = false
                }
            }
        }
    }

    private func fullscreenDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Locked: no brightness/volume (SimpleLive).
                guard !vm.isControlsLocked else { return }
                let w = max(size.width, 1)
                let h = max(size.height, 1)
                if !gestureActive {
                    // Start only from middle vertical band (SimpleLive 25%–75%).
                    let y = value.startLocation.y
                    guard y > h * 0.2, y < h * 0.8 else { return }
                    gestureActive = true
                    gestureIsLeft = value.startLocation.x < w / 2
                    gestureBaseBrightness = LiveSystemBrightness.current
                    gestureBaseVolume = LiveSystemVolume.current
                }
                guard gestureActive else { return }
                // Drag up → increase; drag down → decrease.
                let delta = (value.startLocation.y - value.location.y) / max(h * 0.55, 1)
                if gestureIsLeft {
                    let next = max(0, min(1, gestureBaseBrightness + CGFloat(delta)))
                    LiveSystemBrightness.set(next)
                    gestureTip = String(format: "亮度 %d%%", Int((next * 100).rounded()))
                } else {
                    let next = max(0, min(1, gestureBaseVolume + Float(delta)))
                    LiveSystemVolume.set(next)
                    // Snap tip to 5% steps like SimpleLive.
                    let pct = Int((next * 100 / 5).rounded()) * 5
                    gestureTip = "音量 \(pct)%"
                }
            }
            .onEnded { _ in
                gestureActive = false
                withAnimation(.easeOut(duration: 0.25)) {
                    gestureTip = nil
                }
            }
    }
}

// MARK: - In-room web player

struct LiveRoomWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        // Same pure-playback session as VLC so BT headsets stay on A2DP (not HFP).
        LiveAudioSession.activateForPlayback()
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        if #available(iOS 15.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        // Isolate process — a site crash should not take down the whole app.
        if #available(iOS 14.0, *) {
            let pool = WKProcessPool()
            config.processPool = pool
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = true
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .black
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
        // Mute any residual media elements before tear-down (avoids ghost audio under another surface).
        uiView.evaluateJavaScript(
            "document.querySelectorAll('video,audio').forEach(function(e){try{e.pause();e.muted=true;}catch(_){}})",
            completionHandler: nil
        )
        uiView.navigationDelegate = nil
        LiveAudioSession.deactivateIfNeeded()
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
