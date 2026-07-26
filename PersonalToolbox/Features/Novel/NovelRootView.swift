import SwiftUI

/// 小说阅读 — 书架 / 搜索 / 书源（顶部分段，避免与主 App 底栏叠两层 Tab）
struct NovelRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case shelf = "书架"
        case search = "搜索"
        case sources = "书源"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .shelf: "books.vertical"
            case .search: "magnifyingglass"
            case .sources: "server.rack"
            }
        }
    }

    @State private var section: Section = .shelf
    @State private var path = NavigationPath()
    /// Do not wrap shared singletons in `@State` — SwiftUI would claim ownership.
    private let sources = BookSourceStore.shared
    private let shelf = NovelShelfStore.shared

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("分区", selection: $section) {
                    ForEach(Section.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                Divider()

                Group {
                    switch section {
                    case .shelf:
                        NovelShelfView(path: $path) {
                            withAnimation { section = .sources }
                        }
                    case .search:
                        NovelSearchView(path: $path)
                    case .sources:
                        NovelSourceListView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("小说阅读")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: NovelBook.self) { book in
                NovelDetailView(book: book)
                    .environment(sources)
                    .environment(shelf)
            }
            .onChange(of: section) { _, _ in
                // 切换分段时清空详情栈，避免「搜索进书」后切到书架仍停在详情
                path = NavigationPath()
            }
        }
        .environment(sources)
        .environment(shelf)
    }
}
