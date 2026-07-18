import SwiftUI
import AVKit
import AVFoundation
import UIKit

// MARK: - Home ViewModel (SimpleLive home_list_controller style)

/// Serial loads with cancel — avoids TabView races from concurrent reloads.
@MainActor
final class LiveHomeViewModel: ObservableObject {
    @Published var platform: LivePlatform = .bilibili
    @Published var rooms: [LiveRoomItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var emptyHint: String?
    @Published var searchText = ""
    @Published var categories: [LiveCategory] = []
    @Published var selectedParentId: String?
    @Published var selectedSub: LiveSubCategory?
    @Published var browseMode: BrowseMode = .recommend

    enum BrowseMode: String, CaseIterable, Identifiable {
        case recommend = "推荐"
        case category = "分区"
        var id: String { rawValue }
    }

    private var loadTask: Task<Void, Never>?
    private var hasLoadedOnce = false

    func onTabBecameVisible() {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        // Let TabView finish its transition before network + layout churn.
        reload(delayMs: 80)
    }

    func setPlatform(_ p: LivePlatform) {
        guard p != platform else { return }
        platform = p
        rooms = []
        categories = []
        selectedParentId = nil
        selectedSub = nil
        errorMessage = nil
        emptyHint = nil
        searchText = ""
        browseMode = .recommend
        reload()
    }

    func setBrowseMode(_ mode: BrowseMode) {
        guard mode != browseMode else { return }
        browseMode = mode
        reload()
    }

    func selectParent(_ cat: LiveCategory) {
        selectedParentId = cat.id
        selectedSub = cat.children.first
        reload()
    }

    func selectSub(_ sub: LiveSubCategory) {
        selectedSub = sub
        reload()
    }

    func reload(delayMs: UInt64 = 0) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await self.performReload()
        }
    }

    private func performReload() async {
        isLoading = true
        errorMessage = nil
        emptyHint = nil
        defer { isLoading = false }

        do {
            let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: [LiveRoomItem]
            if !kw.isEmpty {
                result = try await LiveSiteRouter.search(platform: platform, keyword: kw, page: 1)
            } else if browseMode == .category {
                try await loadCategoriesIfNeeded()
                guard !Task.isCancelled else { return }
                if let sub = selectedSub {
                    result = try await LiveSiteRouter.categoryRooms(platform: platform, category: sub, page: 1)
                } else {
                    rooms = []
                    emptyHint = "请选择分区"
                    return
                }
            } else {
                result = try await LiveSiteRouter.recommend(platform: platform, page: 1)
            }
            guard !Task.isCancelled else { return }
            rooms = result
            if rooms.isEmpty {
                emptyHint = defaultEmptyHint
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            rooms = []
            errorMessage = error.localizedDescription
        }
    }

    private func loadCategoriesIfNeeded() async throws {
        guard categories.isEmpty else { return }
        let cats = try await LiveSiteRouter.categories(platform: platform)
        guard !Task.isCancelled else { return }
        categories = cats
        if selectedParentId == nil {
            selectedParentId = cats.first?.id
            selectedSub = cats.first?.children.first
        }
    }

    var defaultEmptyHint: String {
        switch platform {
        case .kuaishou:
            return "暂无数据。试试「分区」或搜索主播 ID。"
        case .douyin:
            return "暂无数据。可切换分区或搜索（可能触发风控）。"
        default:
            return "暂无直播间"
        }
    }

}

// MARK: - Home (list only — room opens fullScreenCover like SimpleLive route)

struct LiveHomeView: View {
    /// When false, skip auto-load and heavy work (TabView off-screen).
    var isTabSelected: Bool = true

    @StateObject private var vm = LiveHomeViewModel()
    @State private var selectedRoom: LiveRoomItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                platformPicker
                modePicker
                searchBar
                if vm.browseMode == .category {
                    categoryBars
                }
                content
            }
            .background(AppleTheme.canvas)
            .navigationTitle("直播")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.reload()
                    } label: {
                        if vm.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(vm.isLoading)
                }
            }
            .onAppear {
                if isTabSelected {
                    vm.onTabBecameVisible()
                }
            }
            .onChange(of: isTabSelected) { _, selected in
                if selected {
                    vm.onTabBecameVisible()
                }
            }
            .fullScreenCover(item: $selectedRoom) { room in
                NavigationStack {
                    LiveRoomView(room: room)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("关闭") { selectedRoom = nil }
                            }
                        }
                }
            }
        }
    }

    // MARK: Chrome

    private func platformTint(_ p: LivePlatform) -> Color {
        switch p {
        case .bilibili: return Color(hex: 0x00A1D6)
        case .huya: return Color(hex: 0xFF8C00)
        case .douyu: return Color(hex: 0xFF6A00)
        case .douyin: return Color(hex: 0x111111)
        case .kuaishou: return Color(hex: 0xFF4906)
        }
    }

    private var platformPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LivePlatform.allCases) { p in
                    let selected = vm.platform == p
                    Button {
                        vm.setPlatform(p)
                    } label: {
                        HStack(spacing: 6) {
                            LivePlatformIcon(platform: p, selected: selected, size: 20)
                            Text(p.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(
                            selected ? platformTint(p) : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var modePicker: some View {
        Picker("模式", selection: Binding(
            get: { vm.browseMode },
            set: { vm.setBrowseMode($0) }
        )) {
            ForEach(LiveHomeViewModel.BrowseMode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Explicit field — avoids TabView + `.searchable` layout crashes on iOS 17.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $vm.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { vm.reload() }
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                    vm.reload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("搜索") { vm.reload() }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var searchPrompt: String {
        vm.platform == .kuaishou ? "搜索主播 / 标题 / 房间号" : "搜索直播间 / 主播"
    }

    @ViewBuilder
    private var categoryBars: some View {
        if vm.categories.isEmpty {
            if vm.isLoading {
                ProgressView().padding(.bottom, 8)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.categories) { cat in
                        Button {
                            vm.selectParent(cat)
                        } label: {
                            Text(cat.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(vm.selectedParentId == cat.id ? Color.white : Color.primary)
                                .background(
                                    vm.selectedParentId == cat.id ? platformTint(vm.platform) : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            if let parent = vm.categories.first(where: { $0.id == vm.selectedParentId }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(parent.children) { sub in
                            Button {
                                vm.selectSub(sub)
                            } label: {
                                Text(sub.name)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(vm.selectedSub?.id == sub.id ? Color.white : Color.primary)
                                    .background(
                                        vm.selectedSub?.id == sub.id ? Color.orange : Color(.secondarySystemFill),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let err = vm.errorMessage, vm.rooms.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("加载失败")
                    .font(.headline)
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("重试") { vm.reload() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !vm.isLoading, vm.rooms.isEmpty {
            VStack(spacing: 12) {
                LivePlatformIcon(platform: vm.platform, selected: false, size: 56)
                Text(vm.platform.title)
                    .font(.headline)
                Text(vm.emptyHint ?? vm.defaultEmptyHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // ScrollView + Button instead of List + NavigationLink (TabView crash vector).
            ScrollView {
                LazyVStack(spacing: 0) {
                    if vm.isLoading && vm.rooms.isEmpty {
                        ProgressView("加载中…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                    ForEach(vm.rooms) { room in
                        Button {
                            selectedRoom = room
                        } label: {
                            roomRow(room)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 148)
                    }
                }
            }
            .refreshable { vm.reload() }
        }
    }

    private func roomRow(_ room: LiveRoomItem) -> some View {
        HStack(spacing: 12) {
            coverView(room.cover)
            VStack(alignment: .leading, spacing: 4) {
                Text(room.title.isEmpty ? "未命名直播间" : room.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(room.userName.isEmpty ? "主播" : room.userName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Self.formatOnline(room.online)) 人气")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func coverView(_ cover: String) -> some View {
        let url = URL(string: cover)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            if let url, url.scheme == "http" || url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(width: 120, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private static func formatOnline(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
        return "\(n)"
    }
}

// MARK: - Platform icon (safe asset / SF fallback)

struct LivePlatformIcon: View {
    let platform: LivePlatform
    var selected: Bool = false
    var size: CGFloat = 20

    var body: some View {
        if UIImage(named: platform.brandAssetName) != nil {
            Image(platform.brandAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.2), style: .continuous))
        } else {
            Image(systemName: platform.systemImage)
                .font(.system(size: max(10, size * 0.55), weight: .semibold))
                .foregroundStyle(selected ? Color.white.opacity(0.9) : tint)
                .frame(width: size, height: size)
        }
    }

    private var tint: Color {
        switch platform {
        case .bilibili: return Color(hex: 0x00A1D6)
        case .huya: return Color(hex: 0xFF8C00)
        case .douyu: return Color(hex: 0xFF6A00)
        case .douyin: return Color(hex: 0x111111)
        case .kuaishou: return Color(hex: 0xFF4906)
        }
    }
}

// MARK: - Room (isolated fullScreen lifecycle; player not inside outer ScrollView)

@MainActor
final class LiveRoomViewModel: ObservableObject {
    let room: LiveRoomItem

    @Published var detail: LiveRoomDetail?
    @Published var qualities: [LivePlayQuality] = []
    @Published var selectedId: String?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var showDanmaku = true
    @Published private(set) var player: AVPlayer?

    private var loadTask: Task<Void, Never>?

    init(room: LiveRoomItem) {
        self.room = room
    }

    func start() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let d = try await LiveSiteRouter.roomDetail(platform: room.platform, roomId: room.roomId)
            guard !Task.isCancelled else { return }
            detail = d
            guard d.isLive else {
                errorMessage = "当前未开播"
                return
            }
            let qs = try await LiveSiteRouter.playQualities(detail: d)
            guard !Task.isCancelled else { return }
            qualities = qs
            guard let first = qs.first else {
                errorMessage = "无可用清晰度"
                return
            }
            selectedId = first.id
            await play(quality: first)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func selectQuality(_ q: LivePlayQuality) {
        selectedId = q.id
        Task { await play(quality: q) }
    }

    private func play(quality: LivePlayQuality) async {
        guard let detail else { return }
        do {
            let result = try await LiveSiteRouter.playURLs(detail: detail, quality: quality)
            guard !Task.isCancelled else { return }
            let ordered = result.urls.filter { URL(string: $0) != nil }.sorted { a, b in
                let am = a.contains(".m3u8")
                let bm = b.contains(".m3u8")
                if am != bm { return am && !bm }
                return false
            }
            guard let first = ordered.first, let url = URL(string: first) else {
                errorMessage = "无可用播放地址"
                return
            }
            let headers = result.headers
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": headers
            ])
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = p
            p.play()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    var webFallback: String {
        switch room.platform {
        case .bilibili: return "https://live.bilibili.com/\(room.roomId)"
        case .huya: return "https://www.huya.com/\(room.roomId)"
        case .douyu: return "https://www.douyu.com/\(room.roomId)"
        case .douyin: return "https://live.douyin.com/\(room.roomId)"
        case .kuaishou: return "https://live.kuaishou.com/u/\(room.roomId)"
        }
    }

}

struct LiveRoomView: View {
    let room: LiveRoomItem
    @StateObject private var vm: LiveRoomViewModel
    @StateObject private var danmaku = LiveDanmakuService()

    init(room: LiveRoomItem) {
        self.room = room
        _vm = StateObject(wrappedValue: LiveRoomViewModel(room: room))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed player band — never nest AVPlayerViewController in ScrollView.
            playerArea
                .frame(height: 220)
                .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if vm.showDanmaku {
                        danmakuPanel
                    }
                    infoArea
                    qualityPicker
                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
        }
        .background(AppleTheme.canvas)
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        vm.showDanmaku.toggle()
                        danmaku.isEnabled = vm.showDanmaku
                        if vm.showDanmaku, let d = vm.detail {
                            softStartDanmaku(d)
                        } else {
                            danmaku.stop()
                        }
                    } label: {
                        Image(systemName: vm.showDanmaku ? "text.bubble.fill" : "text.bubble")
                    }
                    if let url = URL(string: vm.detail?.webURL ?? vm.webFallback),
                       url.scheme == "http" || url.scheme == "https" {
                        Link(destination: url) {
                            Image(systemName: "safari")
                        }
                    }
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear {
            danmaku.stop()
            vm.stop()
        }
        .onChange(of: vm.detail?.roomId) { _, _ in
            // Start danmaku after detail is ready (and play path settled).
            if vm.showDanmaku, let d = vm.detail, d.isLive {
                softStartDanmaku(d)
            }
        }
    }

    private var navTitle: String {
        if let name = vm.detail?.userName, !name.isEmpty { return name }
        return room.userName.isEmpty ? "直播间" : room.userName
    }

    private func softStartDanmaku(_ d: LiveRoomDetail) {
        // Defer one runloop so player layout finishes first.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard vm.showDanmaku else { return }
            danmaku.start(platform: room.platform, danmakuJSON: d.danmakuJSON, roomId: d.roomId)
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        ZStack {
            Color.black
            if let player = vm.player {
                LivePlayerLayerView(player: player)
            } else if vm.isLoading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "play.slash")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var danmakuPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("弹幕")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(danmaku.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(danmaku.messages) { msg in
                            HStack(alignment: .top, spacing: 4) {
                                Text(msg.userName.isEmpty ? "用户" : msg.userName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color(hex: msg.colorHex))
                                Text(msg.text)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                            .id(msg.id)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: danmaku.messages.count) { _, _ in
                    if let last = danmaku.messages.last {
                        // No animation — reduces Tab/layout thrash while streaming.
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.detail?.title ?? room.title)
                .font(.headline)
            HStack {
                Text(vm.detail?.userName ?? room.userName)
                Spacer()
                if let d = vm.detail {
                    Text(d.isLive ? "直播中" : "未开播")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d.isLive ? Color.green : Color.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let intro = vm.detail?.introduction, !intro.isEmpty {
                Text(intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
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

// MARK: - AVPlayerLayer host (lighter / safer than AVPlayerViewController in TabView)

struct LivePlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
