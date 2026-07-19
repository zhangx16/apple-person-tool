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

    private var loadTask: Task<Void, Never>?
    private var failWatchTask: Task<Void, Never>?
    private var headerLoader: LiveHeaderResourceLoader?
    private var avPlayer: AVPlayer?

    /// Exposed for rare AVPlayer fallback (HLS only, no VLC binary).
    var systemPlayer: AVPlayer? { avPlayer }

    init(room: LiveRoomItem) {
        self.room = room
        webURL = URL(string: defaultWebURL)
        // Restore last successful engine for this platform.
        switch LivePlayPrefs.preferred(for: room.platform) {
        case .web: playMode = .web
        case .native: playMode = .native
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
        isControlsLocked = false
        clearStream()
    }

    func retryNative() {
        playMode = .native
        LivePlayPrefs.remember(.native, for: room.platform)
        errorMessage = nil
        start()
    }

    func switchToWeb() {
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
                Task { await warmQualities(detail: d) }
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

    @discardableResult
    private func play(quality: LivePlayQuality) async -> Bool {
        guard let detail else { return false }
        statusText = "拉取线路 \(quality.name)…"
        do {
            let result = try await LiveSiteRouter.playURLs(detail: detail, quality: quality)
            guard !Task.isCancelled else { return false }

            // Prefer order: HLS first (lighter), then FLV (needs VLC), skip empty.
            let ordered = Self.rankURLs(result.urls)
            guard !ordered.isEmpty else {
                errorMessage = nil
                statusText = "无可用地址"
                return false
            }

            for urlString in ordered.prefix(6) {
                guard let url = URL(string: urlString) else { continue }
                let isFLV = urlString.lowercased().contains(".flv")
                statusText = isFLV ? "VLC 播放 FLV…" : "连接 \(quality.name)…"

                #if canImport(MobileVLCKit)
                clearStream()
                streamHeaders = result.headers
                streamIsFLV = isFLV
                streamURL = url
                playMode = .native
                errorMessage = nil
                statusText = "播放中 · \(quality.name)" + (isFLV ? " · FLV" : " · HLS")
                return true
                #else
                if isFLV { continue }
                if await startAVPlayer(url: url, headers: result.headers) {
                    streamIsFLV = false
                    streamURL = url
                    streamHeaders = result.headers
                    playMode = .native
                    errorMessage = nil
                    statusText = "播放中 · \(quality.name)"
                    return true
                }
                #endif
            }
            statusText = "线路均不可用"
            return false
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
    @ObservedObject private var follows = LiveFollowStore.shared
    @State private var isPlayerFullscreen = false
    @State private var showPlayerChrome = true

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
                    if vm.playMode == .native {
                        qualitySection
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPlayerFullscreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("全屏播放")
            }
        }
        .task { vm.start() }
        .onDisappear {
            if !isPlayerFullscreen { vm.stop() }
        }
        .fullScreenCover(isPresented: $isPlayerFullscreen) {
            LiveRoomFullscreenView(vm: vm)
        }
    }

    private var shortTitle: String {
        let n = vm.detail?.userName ?? room.userName
        return n.isEmpty ? "直播间" : n
    }

    // MARK: Player (16:9, overlays like 虎牙/斗鱼/B站)

    private var playerHero: some View {
        GeometryReader { geo in
            ZStack {
                LivePlayerSurface(vm: vm)

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
                            Capsule().fill(brand.gradient)
                        }
                    }
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        }
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
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        }
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
                                            Capsule().fill(brand.gradient)
                                        } else {
                                            Capsule().fill(Color(.tertiarySystemFill))
                                        }
                                    }
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
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
                    subtitle: "VLC · FLV",
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
            HStack(spacing: 10) {
                Button {
                    vm.retryNative()
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(brand)

                Button {
                    isPlayerFullscreen = true
                } label: {
                    Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(brand.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        }
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
            Text("点播放器显示控件；锁图标防误触；全屏后点屏幕切换控制条。")
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

/// Fullscreen player — SimpleLive / 主流直播风格控制条 + 锁定
struct LiveRoomFullscreenView: View {
    @ObservedObject var vm: LiveRoomViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showChrome = true

    private var brand: Color {
        LiveUI.brand(vm.detail?.platform ?? .huya)
    }

    var body: some View {
        ZStack {
            LivePlayerSurface(vm: vm)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !vm.isControlsLocked else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChrome.toggle()
                    }
                }

            if vm.isControlsLocked {
                // Only unlock affordances on both sides (anti mis-touch).
                HStack {
                    unlockSideButton
                    Spacer()
                    unlockSideButton
                }
                .padding(.horizontal, 12)
            } else if showChrome {
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
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.isControlsLocked = true
                                showChrome = false
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
                        .padding(.bottom, 10)
                    }

                    HStack {
                        Text(vm.statusText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
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
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onDisappear {
            // Leaving fullscreen keeps lock state so inline player stays locked if user wants.
        }
    }

    private var unlockSideButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                vm.unlockControls()
                showChrome = true
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
