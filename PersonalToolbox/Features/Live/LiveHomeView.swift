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

    private struct RoomRoute: Hashable {
        let token: UUID
        let room: LiveRoomItem
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
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                // Soft layered background
                LiveHomeBackground()

                VStack(spacing: 0) {
                    topChrome
                    content
                }
            }
            .navigationTitle("直播")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(for: RoomRoute.self) { route in
                LiveRoomView(room: route.room)
            }
        }
    }

    // MARK: - Top chrome

    private var topChrome: some View {
        VStack(spacing: 14) {
            modeTabs
            platformScroller
            if mode == .search {
                searchFields
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var modeTabs: some View {
        HStack(spacing: 6) {
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
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if on {
                            Capsule().fill(LiveUI.brand(platform).gradient)
                        } else {
                            Capsule().fill(Color.clear)
                        }
                    }
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(4)
        .background(Color(.tertiarySystemFill).opacity(0.85), in: Capsule())
        .padding(.horizontal, 16)
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
                        .foregroundStyle(on ? LiveUI.brand(p) : Color.primary.opacity(0.8))
                        .background {
                            Capsule()
                                .fill(on ? LiveUI.brand(p).opacity(0.14) : Color(.secondarySystemGroupedBackground))
                                .shadow(color: on ? LiveUI.brand(p).opacity(0.18) : .black.opacity(0.04), radius: on ? 8 : 3, y: 2)
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(on ? LiveUI.brand(p).opacity(0.35) : Color.clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
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
                TextField("搜索主播 / 房间号", text: $keyword)
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
                        .background(LiveUI.brand(platform).gradient, in: Capsule())
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
        let filtered = follows.items.filter { $0.platform == platform }
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
                    ForEach(filtered) { item in
                        LiveStreamerCard(
                            title: item.title.isEmpty ? item.userName : item.title,
                            subtitle: item.userName.isEmpty ? "房间 \(item.roomId)" : item.userName,
                            meta: "房间 \(item.roomId)",
                            avatarURL: item.cover,
                            brand: LiveUI.brand(platform),
                            trailing: .play
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
                        .swipeActionsCompat {
                            follows.unfollow(item)
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
                    ForEach(searchResults) { room in
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
        path.append(RoomRoute(room: room))
    }

    private func runSearch() async {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else {
            searchError = "请输入搜索关键词"
            return
        }
        searchFocused = false
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            searchResults = try await LiveSiteRouter.search(platform: platform, keyword: kw, page: 1)
            if searchResults.isEmpty {
                searchError = "无结果，试试房间号直达"
            }
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            searchError = error.localizedDescription
        }
    }

    private func openRoomIdDirect() {
        let rid = roomIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else {
            searchError = "请输入房间号"
            return
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
                        .background(brand.gradient, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.isEmpty ? "未命名" : title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                trailingView
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            }
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
                .background(brand.gradient, in: Circle())
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

// Brand gradient helper
private extension Color {
    var gradient: LinearGradient {
        LinearGradient(
            colors: [self, self.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
