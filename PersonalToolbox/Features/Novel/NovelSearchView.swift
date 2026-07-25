import SwiftUI

struct NovelSearchView: View {
    @Environment(BookSourceStore.self) private var sources
    @Environment(NovelShelfStore.self) private var shelf

    @State private var query = ""
    @State private var isSearching = false
    @State private var hits: [NovelSearchHit] = []
    @State private var errors: [String] = []
    @State private var status = ""
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack {
                        TextField("书名 / 作者", text: $query)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                            .onSubmit { Task { await runSearch() } }
                        if isSearching {
                            ProgressView()
                        } else {
                            Button("搜索") { Task { await runSearch() } }
                                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Text("将在 \(sources.nativeEnabledSources.count) 个可用书源中搜索（已排除含 JS 的源）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !status.isEmpty {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !hits.isEmpty {
                    Section("结果 \(hits.count)") {
                        ForEach(hits) { hit in
                            Button {
                                let book = shelf.addFromSearch(hit)
                                path.append(book)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(hit.author.isEmpty ? "未知作者" : hit.author) · \(hit.sourceName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let intro = hit.intro, !intro.isEmpty {
                                        Text(intro)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }

                if !errors.isEmpty {
                    Section("部分书源失败") {
                        ForEach(errors.prefix(8), id: \.self) { e in
                            Text(e)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationDestination(for: NovelBook.self) { book in
                NovelDetailView(book: book)
            }
        }
    }

    private func runSearch() async {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isSearching = true
        status = "搜索中…"
        hits = []
        errors = []
        let src = sources.nativeEnabledSources
        if src.isEmpty {
            status = sources.enabledSources.isEmpty
                ? "请先在「书源」导入 Legado 书源"
                : "已启用书源均含 JS，当前引擎无法搜索。请导入 CSS/JSON 规则书源，或用本地 TXT。"
            isSearching = false
            return
        }
        let result = await NovelBookService.search(key: key, sources: src)
        hits = result.hits
        errors = result.errors
        status = hits.isEmpty
            ? "未找到结果（\(src.count) 个书源）"
            : "完成 · \(hits.count) 条 · \(src.count) 源"
        isSearching = false
    }
}
