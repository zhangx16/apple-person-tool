import SwiftUI

struct NovelSourceListView: View {
    @Environment(BookSourceStore.self) private var store
    @State private var showImport = false
    @State private var filterNativeOnly = true
    @State private var probes: [String: ServiceProbeState] = [:]
    @State private var isVerifyingAll = false

    private var display: [BookSource] {
        let list = store.sources
        if filterNativeOnly {
            return list.filter(\.supportsNativeEngine)
        }
        return list
    }

    var body: some View {
        List {
            Section {
                Toggle("仅显示可本地解析的源", isOn: $filterNativeOnly)
                Text("兼容开源阅读（Legado）JSON。含 JS 的源可导入但不会执行；默认已内置可用 CSS 源。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                LabeledContent("全部书源", value: "\(store.sources.count)")
                LabeledContent("可搜索（无 JS）", value: "\(store.nativeEnabledSources.count)")
                Button {
                    Task { await verifyAll() }
                } label: {
                    Label(isVerifyingAll ? "验证中…" : "全部验证", systemImage: "checkmark.seal")
                }
                .disabled(isVerifyingAll || display.isEmpty)
            }

            if display.isEmpty {
                ContentUnavailableView(
                    "暂无可用书源",
                    systemImage: "server.rack",
                    description: Text("点右上角导入；或先关闭「仅显示可本地解析」查看已导入的 JS 源。")
                )
            } else {
                Section("列表 \(display.count)") {
                    ForEach(display) { source in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.bookSourceName)
                                        .font(.body.weight(.semibold))
                                    Text(source.bookSourceUrl)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        if source.supportsNativeEngine {
                                            badge("CSS/JSON", .green)
                                        } else {
                                            badge("含 JS", .orange)
                                        }
                                        if let g = source.bookSourceGroup, !g.isEmpty {
                                            badge(g, .secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { source.enabled != false },
                                        set: { store.setEnabled($0, for: source.bookSourceUrl) }
                                    )
                                )
                                .labelsHidden()
                            }
                            if let state = probes[source.bookSourceUrl] {
                                ServiceProbeRow(state: state)
                            }
                            Button {
                                Task { await verify(source) }
                            } label: {
                                Label("验证", systemImage: "bolt.fill")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!source.supportsNativeEngine || (probes[source.bookSourceUrl]?.isProbing ?? false))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.delete(id: source.bookSourceUrl)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImport = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("导入书源")
            }
        }
        .sheet(isPresented: $showImport) {
            NovelSourceImportView()
                .environment(store)
        }
        .onAppear { store.load() }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .background(color.opacity(0.15), in: Capsule())
    }

    /// End-to-end check: search → open first hit → list chapters → fetch first chapter's
    /// content. Exercises the exact same call chain the reading flow uses, so a pass here
    /// means the source genuinely works, not just that its domain is reachable.
    @MainActor
    private func verify(_ source: BookSource) async {
        probes[source.bookSourceUrl] = .probing
        let start = ContinuousClock.now
        do {
            let keyword = (source.ruleSearch?.checkKeyWord ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hits = try await NovelBookService.searchOne(
                source: source,
                key: keyword.isEmpty ? "斗破苍穹" : keyword,
                page: 1
            )
            guard let hit = hits.first else {
                probes[source.bookSourceUrl] = .failure("搜索无结果")
                return
            }
            let book = NovelBook(
                id: NovelBook.makeID(sourceURL: hit.sourceURL, bookURL: hit.bookURL),
                name: hit.name,
                author: hit.author,
                coverURL: hit.coverURL,
                intro: hit.intro,
                kind: hit.kind,
                lastChapter: hit.lastChapter,
                wordCount: nil,
                bookURL: hit.bookURL,
                sourceURL: hit.sourceURL,
                sourceName: hit.sourceName,
                isLocal: false,
                localFileName: nil,
                addedAt: Date(),
                lastReadAt: nil,
                lastChapterIndex: 0,
                lastReadOffset: 0
            )
            let chapters = try await NovelBookService.chapters(for: book, source: source)
            guard let firstChapter = chapters.first else {
                probes[source.bookSourceUrl] = .failure("目录为空")
                return
            }
            let text = try await NovelBookService.content(chapter: firstChapter, book: book, source: source)
            guard !text.isEmpty else {
                probes[source.bookSourceUrl] = .failure("正文为空")
                return
            }
            probes[source.bookSourceUrl] = .success(
                latencyMs: Int(start.duration(to: .now) / .milliseconds(1)),
                detail: "\(chapters.count) 章 · 首章 \(text.count) 字"
            )
        } catch {
            probes[source.bookSourceUrl] = .failure(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    @MainActor
    private func verifyAll() async {
        isVerifyingAll = true
        defer { isVerifyingAll = false }
        let targets = display.filter(\.supportsNativeEngine)
        await withTaskGroup(of: Void.self) { group in
            var started = 0
            for source in targets {
                group.addTask { await verify(source) }
                started += 1
                // Stagger slightly and cap concurrency so we don't fire a burst of
                // requests at several different domains all at once.
                if started % 3 == 0 {
                    await group.next()
                }
            }
        }
    }
}

struct NovelSourceImportView: View {
    @Environment(BookSourceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var jsonText = ""
    @State private var message: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(BookSourceStore.recommendedRemotePacks.enumerated()), id: \.offset) { _, pack in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pack.name)
                                .font(.subheadline.weight(.semibold))
                            Text(pack.note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("一键导入") {
                                urlText = pack.url
                                Task { await importURL() }
                            }
                            .disabled(isBusy)
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        Task { await importYiove() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("从 Yiove API 精选导入")
                                .font(.subheadline.weight(.semibold))
                            Text("拉取 shuyuan-api.yiove.com 中 is_valid 且无 JS 的源（接口偶发 5xx）。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isBusy)

                    Button {
                        if store.seedBundledDefaults() {
                            message = "已重新载入内置精选书源（约 \(store.sources.count) 个）。"
                        } else {
                            message = "内置书源文件不存在或已导入过。"
                        }
                    } label: {
                        Text("恢复内置精选书源")
                    }
                    .disabled(isBusy)
                } header: {
                    Text("推荐包（已检查）")
                } footer: {
                    Text("""
                    检查结论（2026-07）：
                    · 内置精选：顶点小说（m.bgg99.cc）与飘天文学已实测可搜；升级后会自动合并。
                    · XIU2 完整包可导入，多数含 JS 本引擎会跳过。
                    · 大灰狼 good.json：GitHub 封锁不可用。Yiove API 偶发 5xx。
                    · ATS 已允许 HTTP；仍建议优先 HTTPS 书源。
                    · 引擎：CSS/JSON 规则；含 <js>/@js: 的源无法搜索。
                    """)
                    .font(.caption2)
                }

                Section("从网络导入") {
                    TextField("书源 JSON 链接", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("导入链接") {
                        Task { await importURL() }
                    }
                    .disabled(isBusy || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("从剪贴板 / 粘贴 JSON") {
                    TextEditor(text: $jsonText)
                        .frame(minHeight: 140)
                        .font(.system(.caption, design: .monospaced))
                    Button("从剪贴板粘贴") {
                        if let s = UIPasteboard.general.string {
                            jsonText = s
                        }
                    }
                    Button("导入 JSON") {
                        Task { await importJSON() }
                    }
                    .disabled(isBusy || jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section {
                    Text("书源格式见开源阅读文档。本引擎：CSS / JSONPath / `##` 替换；不执行 JS。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay {
                if isBusy {
                    ProgressView("导入中…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func importURL() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let n = try await store.importFromURL(urlText)
            message = "成功合并书源，新增约 \(n) 个（同 URL 覆盖）。当前共 \(store.sources.count) 个，可搜索 \(store.nativeEnabledSources.count) 个。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func importJSON() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let n = try store.importJSONString(jsonText)
            message = "成功合并书源，新增约 \(n) 个。当前共 \(store.sources.count) 个。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func importYiove() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let n = try await store.importFromYiove(maxPages: 4, pageSize: 20)
            message = "Yiove 精选导入完成，新增约 \(n) 个无 JS 源。当前可搜索 \(store.nativeEnabledSources.count) 个。"
        } catch {
            message = "Yiove：\(error.localizedDescription)"
        }
    }
}
