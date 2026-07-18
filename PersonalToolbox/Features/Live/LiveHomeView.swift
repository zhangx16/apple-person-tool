import SwiftUI

// MARK: - Home ViewModel

/// Serial cancelable loads (SimpleLive home_list_controller style).
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
    private var didLoad = false

    func ensureLoaded() {
        guard !didLoad else { return }
        didLoad = true
        reload()
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

    func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performReload()
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
        case .kuaishou: return "暂无数据。试试「分区」或搜索主播 ID。"
        case .douyin: return "暂无数据。可切换分区或搜索（可能触发风控）。"
        default: return "暂无直播间"
        }
    }
}

// MARK: - Live tab root (crash-safe shell for modern iOS TabView)

/// Lightweight tab host: does **not** build the real live UI during the tab-switch
/// animation. Heavy content is mounted on the next run loop after selection.
struct LiveHomeView: View {
    var isTabSelected: Bool = true

    /// False until the tab has been selected and the transition can finish.
    @State private var contentMounted = false
    @StateObject private var vm = LiveHomeViewModel()
    @State private var selectedRoom: LiveRoomItem?

    var body: some View {
        // No NavigationStack here — nested stacks under TabView have crashed on
        // several iOS releases. Room uses its own stack inside the cover.
        Group {
            if contentMounted {
                liveContent
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .onAppear { scheduleMountIfNeeded() }
        .onChange(of: isTabSelected) { _, selected in
            if selected {
                scheduleMountIfNeeded()
            }
        }
        .fullScreenCover(item: $selectedRoom, onDismiss: {
            selectedRoom = nil
        }) { room in
            LiveRoomContainer(room: room) {
                selectedRoom = nil
            }
        }
    }

    /// Defer one frame + short delay so TabView layout settles first (iOS 17–27).
    private func scheduleMountIfNeeded() {
        guard isTabSelected, !contentMounted else { return }
        Task { @MainActor in
            // Yield past the current transaction / tab animation.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard isTabSelected else { return }
            contentMounted = true
            // Network only after UI is on screen.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard isTabSelected else { return }
            vm.ensureLoaded()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("直播")
                .font(.headline)
            Text("正在准备…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var liveContent: some View {
        VStack(spacing: 0) {
            headerBar
            platformPicker
            modePicker
            searchBar
            if vm.browseMode == .category {
                categoryBars
            }
            roomList
        }
    }

    // MARK: Chrome

    private var headerBar: some View {
        HStack {
            Text("直播")
                .font(.largeTitle.bold())
            Spacer()
            Button {
                vm.reload()
            } label: {
                if vm.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                }
            }
            .disabled(vm.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func platformTint(_ p: LivePlatform) -> Color {
        // System colors only — avoid custom Color(hex:) / asset lookups on first paint.
        switch p {
        case .bilibili: return .blue
        case .huya: return .orange
        case .douyu: return .orange
        case .douyin: return .primary
        case .kuaishou: return .red
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
                            Image(systemName: p.systemImage)
                                .font(.system(size: 12, weight: .semibold))
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                vm.platform == .kuaishou ? "搜索主播 / 标题 / 房间号" : "搜索直播间 / 主播",
                text: $vm.searchText
            )
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
    private var roomList: some View {
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
                Image(systemName: vm.platform.systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(platformTint(vm.platform))
                Text(vm.platform.title)
                    .font(.headline)
                Text(vm.emptyHint ?? vm.defaultEmptyHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("重新加载") { vm.reload() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if vm.isLoading && vm.rooms.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("加载中…")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(vm.rooms) { room in
                    Button {
                        selectedRoom = room
                    } label: {
                        roomRow(room)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
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
        .padding(.vertical, 4)
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

// MARK: - Room container (owns NavigationStack outside TabView)

struct LiveRoomContainer: View {
    let room: LiveRoomItem
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            LiveRoomView(room: room)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭", action: onClose)
                    }
                }
        }
    }
}
