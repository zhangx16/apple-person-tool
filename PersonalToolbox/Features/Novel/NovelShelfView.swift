import SwiftUI

struct NovelShelfView: View {
    @Environment(NovelShelfStore.self) private var shelf
    @State private var showLocalImport = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if shelf.books.isEmpty {
                    ContentUnavailableView {
                        Label("书架是空的", systemImage: "books.vertical")
                    } description: {
                        Text("从「搜索」用书源找书，或导入本地 TXT。\n书源格式兼容开源阅读（Legado）。")
                    } actions: {
                        Button("导入本地 TXT") { showLocalImport = true }
                        Button("去书源管理") { /* parent tab */ }
                    }
                } else {
                    List {
                        ForEach(shelf.books) { book in
                            NavigationLink(value: book) {
                                NovelBookRow(book: book)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                shelf.remove(bookID: shelf.books[i].id)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("书架")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLocalImport = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .accessibilityLabel("导入本地 TXT")
                }
            }
            .navigationDestination(for: NovelBook.self) { book in
                NovelDetailView(book: book)
            }
            .sheet(isPresented: $showLocalImport) {
                NovelLocalImportView { book in
                    path.append(book)
                }
            }
            .onAppear { shelf.load() }
        }
    }
}

struct NovelBookRow: View {
    let book: NovelBook

    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(book.sourceName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    if let last = book.lastChapter, !last.isEmpty {
                        Text(last)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var cover: some View {
        let size = CGSize(width: 44, height: 60)
        if let s = book.coverURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            placeholder
                .frame(width: size.width, height: size.height)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "book.closed")
                    .foregroundStyle(.secondary)
            }
    }
}
