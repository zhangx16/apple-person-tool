import SwiftUI
import AVKit
import AVFoundation

/// Live tab — multi-site shell from SimpleLive v1.12.6 (+ Kuaishou live_api).
struct LiveHomeView: View {
    @State private var platform: LivePlatform = .bilibili
    @State private var rooms: [LiveRoomItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var path = NavigationPath()
    @State private var emptyHint: String?

    @State private var categories: [LiveCategory] = []
    @State private var selectedParentId: String?
    @State private var selectedSub: LiveSubCategory?
    @State private var browseMode: BrowseMode = .recommend

    enum BrowseMode: String, CaseIterable {
        case recommend = "推荐"
        case category = "分区"
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                platformPicker
                modePicker
                if browseMode == .category {
                    categoryBars
                }
                content
            }
            .background(AppleTheme.canvas)
            .navigationTitle("直播")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: searchPrompt)
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        if isLoading { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .navigationDestination(for: LiveRoomItem.self) { room in
                LiveRoomView(room: room)
            }
            .task { await reload() }
            .onChange(of: platform) { _, _ in
                rooms = []
                categories = []
                selectedParentId = nil
                selectedSub = nil
                errorMessage = nil
                emptyHint = nil
                searchText = ""
                browseMode = .recommend
                Task { await reload() }
            }
            .onChange(of: browseMode) { _, mode in
                Task {
                    if mode == .category {
                        await loadCategoriesIfNeeded()
                    }
                    await reload()
                }
            }
        }
    }

    private var searchPrompt: String {
        switch platform {
        case .kuaishou: return "搜索主播 / 标题 / 房间号"
        default: return "搜索直播间 / 主播"
        }
    }

    private var platformPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LivePlatform.allCases) { p in
                    Button {
                        platform = p
                        Haptics.light()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: p.systemImage)
                            Text(p.title)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(platform == p ? Color.white : Color.primary)
                        .background(
                            platform == p ? Color.accentColor : Color(.tertiarySystemFill),
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
        Picker("模式", selection: $browseMode) {
            ForEach(BrowseMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var categoryBars: some View {
        if categories.isEmpty {
            if isLoading {
                ProgressView().padding(.bottom, 8)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        Button {
                            selectedParentId = cat.id
                            selectedSub = cat.children.first
                            Task { await reload() }
                        } label: {
                            Text(cat.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(selectedParentId == cat.id ? Color.white : Color.primary)
                                .background(
                                    selectedParentId == cat.id ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            if let parent = categories.first(where: { $0.id == selectedParentId }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(parent.children) { sub in
                            Button {
                                selectedSub = sub
                                Task { await reload() }
                            } label: {
                                Text(sub.name)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(selectedSub?.id == sub.id ? Color.white : Color.primary)
                                    .background(
                                        selectedSub?.id == sub.id ? Color.orange : Color(.secondarySystemFill),
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
        if let errorMessage, rooms.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") { Task { await reload() } }
            }
            .frame(maxHeight: .infinity)
        } else if !isLoading, rooms.isEmpty {
            ContentUnavailableView {
                Label(platform.title, systemImage: platform.systemImage)
            } description: {
                Text(emptyHint ?? defaultEmptyHint)
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                if isLoading && rooms.isEmpty {
                    ProgressView("加载中…")
                }
                ForEach(rooms) { room in
                    Button {
                        path.append(room)
                    } label: {
                        roomRow(room)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .refreshable { await reload() }
        }
    }

    private var defaultEmptyHint: String {
        switch platform {
        case .kuaishou:
            return "暂无数据。试试「分区」或搜索主播 ID。"
        case .douyin:
            return "暂无数据。可切换分区或搜索（可能触发风控）。"
        default:
            return "暂无直播间"
        }
    }

    private func roomRow(_ room: LiveRoomItem) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: room.cover)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(room.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(room.userName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Self.formatOnline(room.online)) 人气")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func loadCategoriesIfNeeded() async {
        guard categories.isEmpty else { return }
        do {
            let cats = try await LiveSiteRouter.categories(platform: platform)
            categories = cats
            if selectedParentId == nil {
                selectedParentId = cats.first?.id
                selectedSub = cats.first?.children.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        emptyHint = nil
        defer { isLoading = false }
        do {
            let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !kw.isEmpty {
                rooms = try await LiveSiteRouter.search(platform: platform, keyword: kw, page: 1)
            } else if browseMode == .category {
                await loadCategoriesIfNeeded()
                if let sub = selectedSub {
                    rooms = try await LiveSiteRouter.categoryRooms(platform: platform, category: sub, page: 1)
                } else {
                    rooms = []
                    emptyHint = "请选择分区"
                }
            } else {
                rooms = try await LiveSiteRouter.recommend(platform: platform, page: 1)
            }
            if rooms.isEmpty, errorMessage == nil {
                emptyHint = defaultEmptyHint
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func search() async {
        await reload()
    }

    private static func formatOnline(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
        return "\(n)"
    }
}

struct LiveRoomView: View {
    let room: LiveRoomItem
    @State private var detail: LiveRoomDetail?
    @State private var qualities: [LivePlayQuality] = []
    @State private var selectedId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var player: AVPlayer?
    @StateObject private var danmaku = LiveDanmakuService()
    @State private var showDanmaku = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                playerArea
                if showDanmaku {
                    danmakuPanel
                }
                infoArea
                qualityPicker
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .background(AppleTheme.canvas)
        .navigationTitle(detail?.userName ?? room.userName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showDanmaku.toggle()
                        danmaku.isEnabled = showDanmaku
                        if showDanmaku, let d = detail {
                            danmaku.start(platform: room.platform, danmakuJSON: d.danmakuJSON, roomId: d.roomId)
                        } else {
                            danmaku.stop()
                        }
                    } label: {
                        Image(systemName: showDanmaku ? "text.bubble.fill" : "text.bubble")
                    }
                    if let url = URL(string: detail?.webURL ?? webFallback) {
                        Link(destination: url) {
                            Image(systemName: "safari")
                        }
                    }
                }
            }
        }
        .task { await load() }
        .onDisappear {
            player?.pause()
            player = nil
            danmaku.stop()
        }
    }

    private var webFallback: String {
        switch room.platform {
        case .bilibili: return "https://live.bilibili.com/\(room.roomId)"
        case .huya: return "https://www.huya.com/\(room.roomId)"
        case .douyu: return "https://www.douyu.com/\(room.roomId)"
        case .douyin: return "https://live.douyin.com/\(room.roomId)"
        case .kuaishou: return "https://live.kuaishou.com/u/\(room.roomId)"
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .frame(height: 220)
            if let player {
                LiveAVPlayerView(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if isLoading {
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
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(danmaku.messages) { msg in
                            HStack(alignment: .top, spacing: 4) {
                                Text(msg.userName)
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
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail?.title ?? room.title)
                .font(.headline)
            HStack {
                Text(detail?.userName ?? room.userName)
                Spacer()
                if let d = detail {
                    Text(d.isLive ? "直播中" : "未开播")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d.isLive ? Color.green : Color.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let intro = detail?.introduction, !intro.isEmpty {
                Text(intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
    }

    @ViewBuilder
    private var qualityPicker: some View {
        if !qualities.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(qualities) { q in
                        Button {
                            selectedId = q.id
                            Task { await play(quality: q) }
                        } label: {
                            Text(q.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(selectedId == q.id ? Color.white : Color.primary)
                                .background(
                                    selectedId == q.id ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let d = try await LiveSiteRouter.roomDetail(platform: room.platform, roomId: room.roomId)
            detail = d
            guard d.isLive else {
                errorMessage = "当前未开播"
                return
            }
            let qs = try await LiveSiteRouter.playQualities(detail: d)
            qualities = qs
            guard let first = qs.first else {
                errorMessage = "无可用清晰度"
                return
            }
            selectedId = first.id
            await play(quality: first)
            if showDanmaku {
                danmaku.start(platform: room.platform, danmakuJSON: d.danmakuJSON, roomId: d.roomId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func play(quality: LivePlayQuality) async {
        guard let detail else { return }
        do {
            let result = try await LiveSiteRouter.playURLs(detail: detail, quality: quality)
            let ordered = result.urls.sorted { a, b in
                let am = a.contains(".m3u8")
                let bm = b.contains(".m3u8")
                if am != bm { return am && !bm }
                return false
            }
            guard let first = ordered.first, let url = URL(string: first) else {
                errorMessage = "无可用播放地址"
                return
            }
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": result.headers
            ])
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            player?.pause()
            player = p
            p.play()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LiveAVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

