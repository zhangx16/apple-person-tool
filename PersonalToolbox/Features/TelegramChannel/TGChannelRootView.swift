import SwiftUI

/// 频道片库：连接自建 tg-channel-api，浏览并播放 Telegram 频道视频。
struct TGChannelRootView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var channels: [TGChannelInfo] = []
    @State private var selectedUsername: String = "lihaiPan"
    @State private var posts: [TGPost] = []
    @State private var total = 0
    @State private var videoOnly = true
    @State private var query = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var status = ""
    @State private var playRequest: PlayPayload?

    private struct PlayPayload: Identifiable {
        let id = UUID()
        let title: String
        let request: URLRequest
    }

    private let defaultChannels = ["lihaiPan", "lihaibili"]

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
                        description: Text("确认服务已 login 并完成同步；若频道只有外链，列表会显示但无法 App 内播。")
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
        .fullScreenCover(item: $playRequest) { payload in
            TGChannelPlayerView(title: payload.title, request: payload.request)
        }
    }

    private var channelUsernames: [String] {
        let fromAPI = channels.map(\.username)
        if fromAPI.isEmpty { return defaultChannels }
        var set = fromAPI
        for d in defaultChannels where !set.contains(where: { $0.caseInsensitiveCompare(d) == .orderedSame }) {
            set.append(d)
        }
        return set
    }

    private func titleFor(_ username: String) -> String {
        if let c = channels.first(where: { $0.username.caseInsensitiveCompare(username) == .orderedSame }) {
            return c.displayTitle
        }
        return "@\(username)"
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
                    Button("播放") {
                        Task { await play(post) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
    }

    private func bootstrap() async {
        guard settings.isTGChannelConfigured else { return }
        do {
            let client = try TGChannelClient.fromSettings(settings)
            channels = try await client.channels()
            if let first = channels.first {
                selectedUsername = first.username
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
            status = "已加载 \(posts.count) 条"
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
            try await Task.sleep(nanoseconds: 1_500_000_000)
            await reload(reset: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(_ post: TGPost) async {
        do {
            let client = try TGChannelClient.fromSettings(settings)
            let req = try await client.playRequest(for: post)
            playRequest = PlayPayload(title: String(post.titleLine.prefix(40)), request: req)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
