import SwiftUI

/// 频道片库：连接自建 tg-channel-api，按博主分类浏览，边播边缓存。
struct TGChannelRootView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var channels: [TGChannelInfo] = []
    @State private var selectedUsername: String = "lihaibili"
    @State private var posts: [TGPost] = []
    @State private var creators: [TGCreatorInfo] = []
    @State private var selectedCreator: String = "全部"
    @State private var total = 0
    @State private var videoOnly = true
    @State private var query = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var status = ""
    @State private var playPayload: PlayPayload?
    @State private var cacheTotalBytes: Int64 = 0
    @State private var cacheFileCount = 0
    @State private var confirmClearAll = false
    @State private var deletingId: String?

    private struct PlayPayload: Identifiable {
        let id = UUID()
        let title: String
        let streamURL: URL
        let fileSize: Int64?
        let wasCached: Bool
    }

    private let defaultChannels = ["lihaibili", "lihaiPan"]
    private let allCreatorsLabel = "全部"

    var body: some View {
        List {
            filterSection
            actionsSection
            contentSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("TG 片库")
        .navigationBarTitleDisplayMode(.inline)
        .task { await bootstrap() }
        .onChange(of: selectedUsername) { _, _ in
            selectedCreator = allCreatorsLabel
            Task { await reload(reset: true) }
        }
        .onChange(of: videoOnly) { _, _ in
            Task { await reload(reset: true) }
        }
        .onChange(of: selectedCreator) { _, _ in
            Task { await reload(reset: true) }
        }
        .fullScreenCover(item: $playPayload) { payload in
            TGChannelPlayerView(
                title: payload.title,
                streamURL: payload.streamURL,
                fileSizeHint: payload.fileSize,
                wasCached: payload.wasCached
            )
        }
        .confirmationDialog(
            "清空服务器上全部片库缓存？",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("清空全部缓存", role: .destructive) {
                Task { await clearAllCache() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删 VPS 已下载文件，列表仍在。再播放会边下边播并重新缓存。当前约 \(TGPost.formatBytes(cacheTotalBytes) ?? "0")。")
        }
    }

    // MARK: - Sections

    private var filterSection: some View {
        Section {
            if !settings.isTGChannelConfigured {
                Text("请先在「设置」填写 TG 片库地址与 Token。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Picker("频道", selection: $selectedUsername) {
                ForEach(channelUsernames, id: \.self) { u in
                    Text(titleFor(u)).tag(u)
                }
            }

            if !creatorChips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("博主")
                        .font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(creatorChips, id: \.self) { name in
                                creatorChip(name)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Toggle("仅视频", isOn: $videoOnly)

            HStack {
                TextField("搜索文案", text: $query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { Task { await reload(reset: true) } }
                Button("搜索") { Task { await reload(reset: true) } }
                    .disabled(isLoading || !settings.isTGChannelConfigured)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await reload(reset: true) }
            } label: {
                Label(isLoading ? "加载中…" : "刷新列表", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading || !settings.isTGChannelConfigured)

            Button {
                Task { await sync() }
            } label: {
                Label("服务端同步频道", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isLoading || !settings.isTGChannelConfigured)

            if cacheFileCount > 0 || cacheTotalBytes > 0 {
                HStack(alignment: .center) {
                    Label(
                        "缓存 \(cacheFileCount) 个 · \(TGPost.formatBytes(cacheTotalBytes) ?? "0")",
                        systemImage: "internaldrive"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空缓存", role: .destructive) {
                        confirmClearAll = true
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(isLoading)
                }
            } else {
                Text("首次播放会边下边播并缓存到服务器；长按条目可删除单条缓存。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !status.isEmpty {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var contentSection: some View {
        Section {
            if posts.isEmpty, !isLoading {
                ContentUnavailableView(
                    "暂无内容",
                    systemImage: "play.rectangle.on.rectangle",
                    description: Text(
                        selectedCreator == allCreatorsLabel
                            ? "确认服务已同步。油管频道可点「服务端同步」展开私有视频。"
                            : "该博主下暂无条目，试试「全部」或其他博主。"
                    )
                )
            }
            ForEach(posts) { post in
                postRow(post)
            }
            if posts.count < total {
                Button("加载更多") {
                    Task { await reload(reset: false) }
                }
                .disabled(isLoading)
                .frame(maxWidth: .infinity)
            }
        } header: {
            HStack {
                Text(contentHeader)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var contentHeader: String {
        var parts: [String] = []
        if selectedCreator != allCreatorsLabel {
            parts.append(selectedCreator)
        }
        parts.append("\(posts.count)\(total > 0 ? "/\(total)" : "")")
        return parts.joined(separator: " · ")
    }

    private var creatorChips: [String] {
        var names = [allCreatorsLabel]
        for c in creators {
            let n = c.name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty, n != allCreatorsLabel else { continue }
            if !names.contains(n) { names.append(n) }
        }
        // Also include creators seen in current page (API older / filter mismatch).
        for p in posts {
            let n = p.creatorName
            if !names.contains(n) { names.append(n) }
        }
        return names
    }

    @ViewBuilder
    private func creatorChip(_ name: String) -> some View {
        let on = selectedCreator == name
        let count: Int? = {
            if name == allCreatorsLabel { return nil }
            return creators.first(where: { $0.name == name })?.count
        }()
        Button {
            selectedCreator = name
        } label: {
            HStack(spacing: 4) {
                Text(name)
                    .font(.caption.weight(.semibold))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .opacity(0.75)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background {
                if on {
                    Capsule().fill(Color.accentColor)
                } else {
                    Capsule().fill(Color(.tertiarySystemFill))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row

    @ViewBuilder
    private func postRow(_ post: TGPost) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Leading play control (centered vertically in the row).
            if post.hasVideo {
                Button {
                    Task { await play(post) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "play.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("全屏播放")
            } else {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 52)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(post.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(post.creatorName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)

                    if post.hasVideo {
                        if let d = post.durationText {
                            Label(d, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let size = post.fileSizeText {
                            Text(size)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if post.cached {
                            Label("已缓存", systemImage: "internaldrive.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                if !post.dateText.isEmpty {
                    Text(post.dateText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            if post.hasVideo {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard post.hasVideo else { return }
            Task { await play(post) }
        }
        .contextMenu {
            if post.hasVideo {
                Button {
                    Task { await play(post) }
                } label: {
                    Label("全屏播放", systemImage: "play.rectangle.fill")
                }
                if post.cached {
                    Button(role: .destructive) {
                        Task { await deleteCache(post) }
                    } label: {
                        Label("删除服务器缓存", systemImage: "trash")
                    }
                }
                Button {
                    selectedCreator = post.creatorName
                } label: {
                    Label("只看 \(post.creatorName)", systemImage: "person.crop.circle")
                }
            }
            if let link = post.tgLink, let url = URL(string: link) {
                Link(destination: url) {
                    Label("在 Telegram 打开", systemImage: "paperplane")
                }
            }
        }
    }

    // MARK: - Data

    private var channelUsernames: [String] {
        let fromAPI = channels.map(\.username)
        var set: [String] = []
        for d in defaultChannels where !set.contains(where: { $0.caseInsensitiveCompare(d) == .orderedSame }) {
            set.append(d)
        }
        for u in fromAPI where !set.contains(where: { $0.caseInsensitiveCompare(u) == .orderedSame }) {
            if u.range(of: #"^c\d+$"#, options: .regularExpression) != nil { continue }
            set.append(u)
        }
        return set.isEmpty ? defaultChannels : set
    }

    private func titleFor(_ username: String) -> String {
        if let c = channels.first(where: { $0.username.caseInsensitiveCompare(username) == .orderedSame }) {
            return c.displayTitle
        }
        switch username.lowercased() {
        case "lihaibili": return "B站 · @lihaibili"
        case "lihaipan": return "油管 · @lihaiPan"
        default: return "@\(username)"
        }
    }

    private func bootstrap() async {
        guard settings.isTGChannelConfigured else { return }
        do {
            let client = try TGChannelClient.fromSettings(settings)
            channels = try await client.channels()
            let names = channelUsernames
            if !names.contains(where: { $0.caseInsensitiveCompare(selectedUsername) == .orderedSame }),
               let first = names.first {
                selectedUsername = first
            }
            await reload(reset: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reload(reset: Bool) async {
        guard settings.isTGChannelConfigured else {
            error = TGChannelClientError.notConfigured.localizedDescription
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let client = try TGChannelClient.fromSettings(settings)
            let offset = reset ? 0 : posts.count
            let creatorFilter = selectedCreator == allCreatorsLabel ? nil : selectedCreator
            let res = try await client.posts(
                username: selectedUsername,
                limit: 40,
                offset: offset,
                videoOnly: videoOnly,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                creator: creatorFilter
            )
            if reset {
                posts = res.items
            } else {
                let existing = Set(posts.map(\.id))
                posts.append(contentsOf: res.items.filter { !existing.contains($0.id) })
            }
            total = res.total ?? posts.count
            if let list = res.creators, !list.isEmpty {
                creators = list
            }
            if let t = res.cacheTotalBytes { cacheTotalBytes = t }
            if let c = res.cacheFileCount { cacheFileCount = c }
            status = "已加载 \(posts.count) 条"
            if let stats = try? await client.cacheStats() {
                cacheTotalBytes = stats.totalBytes ?? cacheTotalBytes
                cacheFileCount = stats.fileCount ?? cacheFileCount
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sync() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let client = try TGChannelClient.fromSettings(settings)
            try await client.triggerSync()
            status = "同步已触发，正在刷新…"
            try await Task.sleep(nanoseconds: 3_000_000_000)
            await reload(reset: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(_ post: TGPost) async {
        do {
            let client = try TGChannelClient.fromSettings(settings)
            let url = try client.playURL(for: post)
            playPayload = PlayPayload(
                title: String(post.displayTitle.prefix(48)),
                streamURL: url,
                fileSize: post.fileSize.map { Int64($0) },
                wasCached: post.cached
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteCache(_ post: TGPost) async {
        deletingId = post.id
        error = nil
        defer { deletingId = nil }
        do {
            let client = try TGChannelClient.fromSettings(settings)
            let res = try await client.deleteCache(postId: post.id)
            let freed = TGPost.formatBytes(res.freedBytes) ?? "0"
            status = res.deleted == true ? "已删缓存，释放 \(freed)" : "该条目本无服务器缓存"
            if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                posts[idx] = patched(post: posts[idx], cached: false, cacheBytes: 0)
            }
            if let stats = try? await client.cacheStats() {
                cacheTotalBytes = stats.totalBytes ?? 0
                cacheFileCount = stats.fileCount ?? 0
            } else if let freed = res.freedBytes {
                cacheTotalBytes = max(0, cacheTotalBytes - freed)
                cacheFileCount = max(0, cacheFileCount - 1)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clearAllCache() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let client = try TGChannelClient.fromSettings(settings)
            let res = try await client.clearAllCache()
            let freed = TGPost.formatBytes(res.freedBytes) ?? "0"
            status = "已清空服务器缓存，释放 \(freed)"
            posts = posts.map { patched(post: $0, cached: false, cacheBytes: 0) }
            cacheTotalBytes = 0
            cacheFileCount = 0
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func patched(post: TGPost, cached: Bool, cacheBytes: Int64) -> TGPost {
        guard let data = try? JSONEncoder().encode(TGPostCachePatch(from: post, cached: cached, cacheBytes: cacheBytes)),
              let decoded = try? JSONDecoder().decode(TGPost.self, from: data) else {
            return post
        }
        return decoded
    }
}

private struct TGPostCachePatch: Encodable {
    let id: String
    let channel_id: String
    let message_id: Int
    let date: Double?
    let text: String?
    let media_type: String?
    let has_video: Bool
    let duration: Double?
    let width: Int?
    let height: Int?
    let file_size: Int?
    let file_name: String?
    let mime_type: String?
    let external_urls: [String]
    let channel_username: String?
    let play_path: String?
    let tg_link: String?
    let cached: Bool
    let cache_bytes: Int64
    let creator: String?

    init(from post: TGPost, cached: Bool, cacheBytes: Int64) {
        id = post.id
        channel_id = post.channelId
        message_id = post.messageId
        date = post.date
        text = post.text
        media_type = post.mediaType
        has_video = post.hasVideo
        duration = post.duration
        width = post.width
        height = post.height
        file_size = post.fileSize
        file_name = post.fileName
        mime_type = post.mimeType
        external_urls = post.externalUrls
        channel_username = post.channelUsername
        play_path = post.playPath
        tg_link = post.tgLink
        self.cached = cached
        self.cache_bytes = cacheBytes
        creator = post.creator ?? post.creatorName
    }
}
