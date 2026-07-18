import SwiftUI
import UIKit

/// Live tab — 关注 + 搜索 + 应用内播放（无推荐）。
///
/// Room opens as a **pushed page** (NavigationStack), not a sheet popup.
struct LiveHomeView: View {
    private enum MainMode: String, CaseIterable, Identifiable {
        case follow = "关注"
        case search = "搜索"
        var id: String { rawValue }
    }

    /// Hashable route so the same room can be opened again after pop.
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

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                modePicker
                platformBar
                Divider()
                if mode == .follow {
                    followList
                } else {
                    searchPanel
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("直播")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: RoomRoute.self) { route in
                LiveRoomView(room: route.room)
            }
        }
    }

    private func openRoom(_ room: LiveRoomItem) {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        path.append(RoomRoute(room: room))
    }

    // MARK: - Chrome

    private var modePicker: some View {
        Picker("模式", selection: $mode) {
            ForEach(MainMode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var platformBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LivePlatform.allCases) { p in
                    let on = platform == p
                    Button {
                        platform = p
                        if mode == .search {
                            searchResults = []
                            searchError = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: p.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                            Text(p.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Follow

    @ViewBuilder
    private var followList: some View {
        let filtered = follows.items.filter { $0.platform == platform }
        if filtered.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "heart")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("还没有关注的\(platform.title)主播")
                    .font(.headline)
                Text("到「搜索」找主播点星标，或输入房间号打开。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button("去搜索") { mode = .search }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filtered) { item in
                    roomRow(
                        title: item.title.isEmpty ? item.userName : item.title,
                        subtitle: item.userName.isEmpty ? "房间 \(item.roomId)" : "\(item.userName) · \(item.roomId)",
                        cover: item.cover,
                        showPlay: true
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openRoom(follows.asRoomItem(item))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            follows.unfollow(item)
                        } label: {
                            Label("取消关注", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Search

    private var searchPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("主播名 / 房间号关键词", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await runSearch() } }
                    Button("搜索") {
                        Task { await runSearch() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isSearching)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 8) {
                    TextField("房间号直接打开", text: $roomIdInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    Button("打开") {
                        openRoomIdDirect()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if let searchError {
                Text(searchError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            if isSearching {
                ProgressView("搜索中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("搜索后点左侧进入播放，点星标关注")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(searchResults) { room in
                        HStack(spacing: 8) {
                            roomRow(
                                title: room.title.isEmpty ? room.userName : room.title,
                                subtitle: {
                                    let name = room.userName.isEmpty ? "主播" : room.userName
                                    let online = room.online > 0 ? " · \(Self.formatOnline(room.online)) 人气" : ""
                                    return "\(name)\(online)"
                                }(),
                                cover: room.cover,
                                showPlay: true
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { openRoom(room) }

                            Button {
                                toggleFollow(room)
                            } label: {
                                Image(systemName: follows.isFollowing(platform: room.platform, roomId: room.roomId)
                                      ? "star.fill" : "star")
                                    .font(.title3)
                                    .foregroundStyle(
                                        follows.isFollowing(platform: room.platform, roomId: room.roomId)
                                        ? Color.yellow : Color.secondary
                                    )
                                    .frame(width: 44, height: 56)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                        // Explicit secondary action for devices that ignore row taps.
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                openRoom(room)
                            } label: {
                                Label("播放", systemImage: "play.fill")
                            }
                            .tint(.accentColor)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func roomRow(
        title: String,
        subtitle: String,
        cover: String,
        showPlay: Bool
    ) -> some View {
        HStack(spacing: 12) {
            coverView(cover)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? "未命名" : title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showPlay {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
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
                        Image(systemName: "person.crop.square")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.crop.square")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Actions

    private func runSearch() async {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else {
            searchError = "请输入搜索关键词"
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            searchResults = try await LiveSiteRouter.search(platform: platform, keyword: kw, page: 1)
            if searchResults.isEmpty {
                searchError = "无结果，可换关键词或直接用房间号打开"
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
        }
    }

    private static func formatOnline(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
        return "\(n)"
    }
}
