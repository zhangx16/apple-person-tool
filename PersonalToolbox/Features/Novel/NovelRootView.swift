import SwiftUI

/// 小说阅读 — 书架 / 搜索 / 书源（参考开源阅读 Legado 书源体系）
struct NovelRootView: View {
    @State private var tab = 0
    @State private var sources = BookSourceStore.shared
    @State private var shelf = NovelShelfStore.shared

    var body: some View {
        TabView(selection: $tab) {
            NovelShelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
                .tag(0)
            NovelSearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(1)
            NovelSourceListView()
                .tabItem { Label("书源", systemImage: "server.rack") }
                .tag(2)
        }
        .environment(sources)
        .environment(shelf)
        .navigationTitle("小说阅读")
        .navigationBarTitleDisplayMode(.inline)
    }
}
