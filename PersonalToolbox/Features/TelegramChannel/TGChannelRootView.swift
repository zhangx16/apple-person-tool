import SwiftUI

/// 频道片库：连接自建 tg-channel-api，浏览并播放 Telegram 频道视频。
struct TGChannelRootView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var channels: [TGChannelInfo] = []
    @State private var selectedUsername: String = "lihaibili"
    @State private var posts: [TGPost] = []
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
    }

    private let defaultChannels = ["lihaibili", "lihaiPan"]

    var body: some View {
        List {
            Section {
                if !settings.isTGChannelConfigured {
                    Text("请先在「设置」填写 TG 片库地址与 Token（对应 VPS 上 tg-channel-api）。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Picker("频道", selection: $selectedUsername) {
                    ForEach(channelUsernames, id: \.self) { u in
                        Text(titleFor(u)).tag(u)
                    }
                }
                Toggle("仅视频", isOn: $videoOnly)
                HStack {
                    TextField("搜索文案", text: $query)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { Task { await reload(reset: true) } }
                    Button("搜索") { Task { await reload(reset: true) } }
                }
            }

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
                    HStack {
                        Label(
                            "服务器缓存 \(cacheFileCount) 个 · \(TGPost.formatBytes(cacheTotalBytes) ?? "0")",
                            systemImage: "internaldrive"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("清空", role: .destructive) {
                            confirmClearAll = true
                        }
                        .font(.caption.weight(.semibold))
                        .disabled(isLoading)
                    }
                } else {
                    Text("播放时会把视频缓存到 VPS 硬盘，便于 Range 流式播放；可点条目「删缓存」释放空间。")
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

            Section("内容 \(posts.count)\(total > 0 ? " / \(total)" : "")") {
                if posts.isEmpty, !isLoading {
                    ContentUnavailableView(
                        "暂无内容",
                        systemImage: "play.rectangle.on.rectangle",
                        description: Text("确认服务已 login 并完成同步。油管频道若只有公告，点「服务端同步」会展开私有存储里的视频。")
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
                }
            }
        }
        .navigationTitle("TG 片库")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await bootstrap()
        }
        .onChange(of: selectedUsername) { _, _ in
            Task { await reload(reset: true) }
        }
        .onChange(of: videoOnly) { _, _ in
            Task { await reload(reset: true) }
        }
        .fullScreenCover(item: $playPayload) { payload in
            TGChannelPlayerView(
                title: payload.title,
                streamURL: payload.streamURL,
                fileSizeHint: payload.fileSize
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
            Text("只删 VPS 上已下载的文件，列表仍在。下次播放会重新从 Telegram 拉到服务器。当前约 \(TGPost.formatBytes(cacheTotalBytes) ?? "0")。")
        }
    }

    private var channelUsernames: [String] {
        let fromAPI = channels.map(\.username).filter { !$0.hasPrefix("c") || $0.count < 6 }
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

    @ViewBuilder
    private func postRow(_ post: TGPost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.titleLine)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
            HStack(spacing: 8) {
                if post.hasVideo {
                    Label(post.durationText ?? "视频", systemImage: "play.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    if let size = post.fileSizeText {
                        Text(size)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if post.cached {
                        Label(post.cacheSizeText.map { "已缓存 \($0)" } ?? "已缓存", systemImage: "internaldrive.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                } else if !post.externalUrls.isEmpty {
                    Label("外链", systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Label(post.mediaType ?? "文本", systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !post.dateText.isEmpty {
                    Text(post.dateText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 12) {
                if post.hasVideo {
                    Button {
                        Task { await play(post) }
                    } label: {
                        Label("全屏播放", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if post.cached {
                        Button(role: .destructive) {
                            Task { await deleteCache(post) }
                        } label: {
                            if deletingId == post.id {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("删缓存", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(deletingId != nil)
                    }
                }
                if let link = post.tgLink, let url = URL(string: link) {
                    Link("Telegram", destination: url)
                        .font(.caption)
                }
                if let first = post.externalUrls.first, let url = URL(string: first) {
                    Link("打开链接", destination: url)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard post.hasVideo else { return }
            Task { await play(post) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if post.hasVideo, post.cached {
                Button(role: .destructive) {
                    Task { await deleteCache(post) }
                } label: {
                    Label("删缓存", systemImage: "trash")
                }
            }
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
            let res = try await client.posts(
                username: selectedUsername,
                limit: 40,
                offset: offset,
                videoOnly: videoOnly,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if reset {
                posts = res.items
            } else {
                let existing = Set(posts.map(\.id))
                posts.append(contentsOf: res.items.filter { !existing.contains($0.id) })
            }
            total = res.total ?? posts.count
            if let t = res.cacheTotalBytes { cacheTotalBytes = t }
            if let c = res.cacheFileCount { cacheFileCount = c }
            status = "已加载 \(posts.count) 条"
            // Refresh aggregate cache even when list page has no cached items.
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
            status = "同步已触发（含油管私有链接展开），正在刷新…"
            try await Task.sleep(nanoseconds: 4_000_000_000)
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
                title: String(post.titleLine.prefix(40)),
                streamURL: url,
                fileSize: post.fileSize.map { Int64($0) }
            )
            // After play starts, server may begin/finish caching — soft refresh later is optional.
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
            status = res.deleted == true ? "已删除缓存，释放 \(freed)" : "该条目本无服务器缓存"
            // Update local row + totals without full reload.
            if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                var updated = posts[idx]
                // TGPost is a struct; re-decode path: patch via reload item fields we can mutate if var
                posts[idx] = patched(post: updated, cached: false, cacheBytes: 0)
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

    /// TGPost has no memberwise init with all fields; rebuild via JSON round-trip for cache flags.
    private func patched(post: TGPost, cached: Bool, cacheBytes: Int64) -> TGPost {
        // Encode minimal patch by reusing decoder path from a synthetic dictionary is heavy;
        // simplest: mutate via Mirror-free approach — re-fetch list is fine, but for snappy UI
        // we encode/decode with JSONSerialization.
        guard var obj = try? JSONEncoder().encode(TGPostCachePatch(from: post, cached: cached, cacheBytes: cacheBytes)),
              let decoded = try? JSONDecoder().decode(TGPost.self, from: obj) else {
            return post
        }
        return decoded
    }
}

/// Helper to re-encode a post with updated cache fields (TGPost only has decoder).
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
    }
}
