import SwiftUI

struct NovelDetailView: View {
    @Environment(BookSourceStore.self) private var sources
    @Environment(NovelShelfStore.self) private var shelf

    let book: NovelBook
    @State private var chapters: [NovelChapter] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var readerChapter: NovelChapter?

    private var liveBook: NovelBook {
        shelf.books.first(where: { $0.id == book.id }) ?? book
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(liveBook.name)
                        .font(.title3.weight(.bold))
                    Text(liveBook.author)
                        .foregroundStyle(.secondary)
                    if let intro = liveBook.intro, !intro.isEmpty {
                        Text(intro)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("来源：\(liveBook.sourceName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)

                if !chapters.isEmpty {
                    Button {
                        let idx = min(liveBook.lastChapterIndex, max(0, chapters.count - 1))
                        readerChapter = chapters[idx]
                    } label: {
                        Label(
                            liveBook.lastReadAt == nil ? "开始阅读" : "继续阅读 · \(chapters[safe: liveBook.lastChapterIndex]?.name ?? "")",
                            systemImage: "book"
                        )
                    }
                }
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("加载目录…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("重试") { Task { await loadChapters() } }
                }
            } else {
                Section("目录 \(chapters.count) 章") {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, ch in
                        Button {
                            readerChapter = ch
                            shelf.updateProgress(bookID: book.id, chapterIndex: index, offset: 0)
                        } label: {
                            HStack {
                                Text(ch.name)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if index == liveBook.lastChapterIndex {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadChapters() }
        .fullScreenCover(item: $readerChapter) { ch in
            NovelReaderView(
                book: liveBook,
                chapters: chapters,
                initialChapter: ch
            )
        }
    }

    private func loadChapters() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let source = sources.source(url: book.sourceURL)
            chapters = try await NovelBookService.chapters(for: book, source: source)
        } catch {
            self.error = error.localizedDescription
            chapters = []
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
