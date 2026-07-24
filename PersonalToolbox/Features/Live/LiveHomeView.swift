import SwiftUI
import UIKit

/// Live tab — modern card UI (主流 App 风格：留白、圆角、轻阴影、层级清晰)
struct LiveHomeView: View {
    private enum MainMode: String, CaseIterable, Identifiable {
        case follow = "关注"
        case search = "搜索"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .follow: return "heart.fill"
            case .search: return "magnifyingglass"
            }
        }
    }

    private struct RoomRoute: Hashable, Identifiable {
        let token: UUID
        let room: LiveRoomItem
        var id: UUID { token }
        init(room: LiveRoomItem) {
            self.token = UUID()
            self.room = room
        }
    }

    @ObservedObject private var follows = LiveFollowStore.shared
    @State private var mode: MainMode = .follow
    @State private var platform: LivePlatform = .huya
    @State private var keyword = ""
    @State private var roomIdInput = ""
    @State private var searchResults: [LiveRoomItem] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var path = NavigationPath()
    /// B站单独用 sheet 打开，彻底绕开 LiveRoomView / VLC / NavigationPath 组合崩溃。
    @State private var bilibiliSheet: RoomRoute?
    @FocusState private var searchFocused: Bool
    @State private var clipboardRoomHint: String?
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                // Soft layered background
                LiveHomeBackground()

                VStack(spacing: 0) {
                    topChrome
                    if let clipboardRoomHint {
                        clipboardBanner(clipboardRoomHint)
                    }
                    content
                }
            }
            .navigationTitle("直播")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(for: RoomRoute.self) { route in
                // B站不应走进这里；双保险（无 VLC / 无页内 WKWebView）。
                if route.room.platform == .bilibili {
                    BilibiliLiveWebRoomView(room: route.room)
                } else {
                    LiveRoomView(room: route.room)
                }
            }
            // 纯信息 sheet（无 WebView）；真正播放走进程外 SFSafariViewController。
            .sheet(item: $bilibiliSheet) { route in
                NavigationStack {
                    BilibiliLiveWebRoomView(room: route.room)
                }
            }
            .onAppear {
                // B站关注元数据刷新走 get_info；仍跳过自动刷，避免切平台时连发请求。
                if platform != .bilibili {
                    follows.refreshMissingAvatars(for: platform)
                }
                detectClipboardRoomId()
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .follow, platform != .bilibili {
                    follows.refreshMissingAvatars(for: platform)
                }
            }
            .onChange(of: platform) { _, newPlatform in
                if mode == .follow, newPlatform != .bilibili {
                    follows.refreshMissingAvatars(for: newPlatform)
                }
                detectClipboardRoomId()
            }
        }
    }

    private func clipboardBanner(_ rid: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(LiveUI.brand(platform))
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到剪贴板房间号")
                    .font(.caption.weight(.semibold))
                Text(rid)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("打开") {
                openRoom(LiveRoomItem(
                    platform: platform,
                    roomId: rid,
                    title: "",
                    cover: "",
                    userName: "",
                    online: 0
                ))
                clipboardRoomHint = nil
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(LiveUI.brand(platform).brandGradient, in: Capsule())
            Button {
                clipboardRoomHint = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func detectClipboardRoomId() {
        let text = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, text.count <= 24 else {
            clipboardRoomHint = nil
            return
        }
        // Pure digits or alnum room id (huya private host etc.)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            clipboardRoomHint = nil
            return
        }
        // Avoid treating normal words as room ids
        let hasDigit = text.contains { $0.isNumber }
        guard hasDigit || text.count >= 4 else {
            clipboardRoomHint = nil
            return
        }
        clipboardRoomHint = text
    }

    // MARK: - Top chrome

    @Namespace private var modeNamespace

    private var topChrome: some View {
        VStack(spacing: 14) {
            modeTabs
            platformScroller
            if mode == .search {
                searchFields
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var modeTabs: some View {
        HStack(spacing: 0) {
            ForEach(MainMode.allCases) { m in
                let on = mode == m
                Button {
                    withAnimation(AppleTheme.preferredSnappy) { mode = m }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.icon)
                            .font(.caption.weight(.semibold))
                        Text(m.rawValue)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if on {
                            Capsule()
                                .fill(LiveUI.brand(platform).brandGradient)
                                .overlay {
                                    Capsule()
                                        .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                                }
                                .shadow(color: LiveUI.brand(platform).opacity(0.3), radius: 8, y: 3)
                                .matchedGeometryEffect(id: "modeIndicator", in: modeNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var platformScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LivePlatform.allCases) { p in
                    let on = platform == p
                    Button {
                        withAnimation(AppleTheme.preferredSnappy) {
                            platform = p
                            if mode == .search {
                                searchResults = []
                                searchError = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            LivePlatformMark(platform: p, size: 22)
                            Text(p.title)
                                .font(.subheadline.weight(on ? .bold : .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(on ? .white : Color.primary.opacity(0.8))
                        .background {
                            if on {
                                Capsule()
                                    .fill(LiveUI.brand(p).brandGradient)
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                                    }
                                    .shadow(color: LiveUI.brand(p).opacity(0.35), radius: 10, y: 3)
                                // Avoid matchedGeometryEffect here — multi-pill + TabView has
                                // caused intermittent hard crashes on some iOS 17 builds.
                            } else {
                                Capsule()
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.04), radius: 3, y: 2)
                            }
                        }
                        .overlay {
                            if !on {
                                Capsule()
                                    .strokeBorder(AppStroke.subtle, lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(PressableButtonStyle(haptic: false))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private var searchFields: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    platform == .bilibili ? "搜索主播 / 房间号 / live.bilibili.com 链接" : "搜索主播 / 房间号",
                    text: $keyword
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { Task { await runSearch() } }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Task { await runSearch() }
                } label: {
                    Text("搜索")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(LiveUI.brand(platform).brandGradient, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isSearching)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

            HStack(spacing: 10) {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                TextField("房间号直达", text: $roomIdInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.go)
                    .onSubmit { openRoomIdDirect() }
                Button("打开") { openRoomIdDirect() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiveUI.brand(platform))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if mode == .follow {
            followContent
        } else {
            searchContent
        }
    }

    @ViewBuilder
    private var followContent: some View {
        let filtered = follows.items(for: platform)
        if filtered.isEmpty {
            LiveEmptyState(
                symbol: "heart.circle",
                title: "还没有关注",
                message: "在「搜索」里找到常看的主播，点爱心收藏。\n也可以直接输入房间号打开。",
                actionTitle: "去搜索",
                brand: LiveUI.brand(platform)
            ) {
                withAnimation { mode = .search }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if follows.isRefreshingStatus {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在刷新开播状态…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                    ForEach(filtered) { item in
                        // 关注卡：主播名（加粗）→ 房间号 → 分区
                        LiveFollowCard(
                            item: item,
                            brand: LiveUI.brand(platform)
                        ) {
                            openRoom(follows.asRoomItem(item))
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                follows.unfollow(item)
                            } label: {
                                Label("取消关注", systemImage: "heart.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                follows.refreshMetadata(for: platform, forceStatus: true)
                // Brief wait so pull-to-refresh feels responsive.
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if isSearching {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("正在搜索…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let searchError, searchResults.isEmpty {
            LiveEmptyState(
                symbol: "exclamationmark.magnifyingglass",
                title: "搜索失败",
                message: searchError,
                actionTitle: "重试",
                brand: LiveUI.brand(platform)
            ) {
                Task { await runSearch() }
            }
        } else if searchResults.isEmpty {
            LiveEmptyState(
                symbol: "sparkle.magnifyingglass",
                title: "发现主播",
                message: "输入昵称或房间号搜索。\n点爱心加入关注，点卡片进入直播间。",
                actionTitle: nil,
                brand: LiveUI.brand(platform),
                action: nil
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let searchError {
                        Text(searchError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { _, room in
                        let followed = follows.isFollowing(platform: room.platform, roomId: room.roomId)
                        LiveStreamerCard(
                            title: room.title.isEmpty ? room.userName : room.title,
                            subtitle: room.userName.isEmpty ? "主播" : room.userName,
                            meta: room.online > 0 ? "\(Self.formatOnline(room.online)) 人气" : "房间 \(room.roomId)",
                            avatarURL: room.displayAvatar,
                            brand: LiveUI.brand(platform),
                            trailing: .follow(isOn: followed) {
                                toggleFollow(room)
                            }
                        ) {
                            openRoom(room)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Actions

    private func openRoom(_ room: LiveRoomItem) {
        searchFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        if room.platform == .bilibili {
            // 等键盘收起后再 present，避免 “dismiss keyboard + present” 竞态闪退。
            let route = RoomRoute(room: room)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                bilibiliSheet = route
            }
            return
        }
        path.append(RoomRoute(room: room))
    }

    private func runSearch() async {
        var kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else {
            searchError = "请输入搜索关键词"
            return
        }
        // B站：搜索框也可贴直播间链接，归一成 room id（纯函数，不碰 actor）。
        if platform == .bilibili, let rid = LiveBilibiliIDs.extractRoomId(from: kw) {
            kw = rid
        }
        searchFocused = false
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            // Isolate network work; hop back to MainActor for UI state only.
            let plat = platform
            let query = kw
            let rooms = try await LiveSiteRouter.search(platform: plat, keyword: query, page: 1)
            guard !Task.isCancelled else { return }
            searchResults = rooms
            if searchResults.isEmpty {
                searchError = "无结果，试试房间号直达"
            }
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            var msg = error.localizedDescription
            if platform == .douyin {
                msg += " · 可到「设置 → 抖音直播」配置 Cookie"
            } else if platform == .bilibili {
                msg += " · 可到「设置 → B站 Cookie」配置 SESSDATA"
            }
            searchError = msg
        }
    }

    private func openRoomIdDirect() {
        let raw = roomIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            searchError = "请输入房间号"
            return
        }
        // B站支持粘贴 live.bilibili.com 链接或纯房间号。
        let rid: String
        if platform == .bilibili, let extracted = LiveBilibiliIDs.extractRoomId(from: raw) {
            rid = extracted
        } else {
            rid = raw
        }
        searchError = nil
        openRoom(
            LiveRoomItem(
                platform: platform,
                roomId: rid,
                title: "",
                cover: "",
                userName: "",
                online: 0
            )
        )
    }

    private func toggleFollow(_ room: LiveRoomItem) {
        if follows.isFollowing(platform: room.platform, roomId: room.roomId) {
            follows.unfollow(platform: room.platform, roomId: room.roomId)
        } else {
            follows.follow(room)
            // Light haptic if available
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }

    private static func formatOnline(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
        return "\(n)"
    }
}

// MARK: - Modern building blocks

private struct LiveHomeBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.06),
                    Color.clear,
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

private struct LiveEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var brand: Color
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(brand.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(brand.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
            }
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(brand.brandGradient, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 关注专用卡：名称加粗 → 房间号 → 分区 + LIVE 角标
private struct LiveFollowCard: View {
    let item: LiveFollowItem
    let brand: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    avatar
                    if item.isLive == true {
                        LiveBadge(size: .small)
                            .offset(x: 6, y: 6)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.displayName)
                            .font(.body.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if item.isLive == true {
                            Text("直播中")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.brandGradient, in: Capsule())
                        } else if item.isLive == false {
                            StatusPill(title: "未开播", color: .secondary)
                        }
                    }
                    Text("房间 \(item.roomId)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption2)
                        Text(item.categoryName.isEmpty ? "分区获取中…" : item.categoryName)
                            .font(.caption)
                        if item.online > 0 {
                            Text("·")
                            Text("\(formatOnline(item.online)) 人气")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(brand.brandGradient, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                    }
                    .shadow(color: brand.opacity(0.3), radius: 8, y: 3)
            }
            .padding(14)
            .appCardV2(corner: 18, padding: 0)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(brand.opacity(0.12))
            if let url = URL(string: item.displayAvatar),
               url.scheme == "http" || url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .foregroundStyle(brand.opacity(0.7))
                    }
                }
            } else {
                Image(systemName: "person.fill")
                    .foregroundStyle(brand.opacity(0.7))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay {
            if item.isLive == true {
                Circle()
                    .strokeBorder(brand.brandGradient, lineWidth: 2)
            } else {
                Circle()
                    .strokeBorder(brand.opacity(0.2), lineWidth: 1.5)
            }
        }
    }

    private func formatOnline(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
        return "\(n)"
    }
}

private enum LiveCardTrailing {
    case play
    case follow(isOn: Bool, action: () -> Void)
}

private struct LiveStreamerCard: View {
    let title: String
    let subtitle: String
    let meta: String
    let avatarURL: String
    let brand: Color
    let trailing: LiveCardTrailing
    /// Follow list: bold name on top; search keeps medium weight.
    var emphasizeName: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: emphasizeName ? 5 : 4) {
                    Text(title.isEmpty ? "未命名" : title)
                        .font(emphasizeName ? .body.weight(.bold) : .body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(emphasizeName ? 1 : 2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !meta.isEmpty {
                        HStack(spacing: 4) {
                            if emphasizeName {
                                Image(systemName: "square.grid.2x2")
                                    .font(.caption2)
                            }
                            Text(meta)
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                trailingView
            }
            .padding(14)
            .appCardV2(corner: 18, padding: 0)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(brand.opacity(0.12))
            if let url = URL(string: avatarURL), url.scheme == "http" || url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .foregroundStyle(brand.opacity(0.7))
                    }
                }
            } else {
                Image(systemName: "person.fill")
                    .foregroundStyle(brand.opacity(0.7))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay(Circle().stroke(brand.opacity(0.2), lineWidth: 1.5))
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .play:
            Image(systemName: "play.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(brand.brandGradient, in: Circle())
        case .follow(let isOn, let action):
            Button(action: action) {
                Image(systemName: isOn ? "heart.fill" : "heart")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isOn ? Color.pink : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(isOn ? Color.pink.opacity(0.12) : Color(.tertiarySystemFill))
                    )
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}

/// Soft swipe-to-delete without List (ScrollView cards).
private extension View {
    func swipeActionsCompat(delete: @escaping () -> Void) -> some View {
        // Context menu covers delete; keep API for call sites.
        self
    }
}
