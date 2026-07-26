import SwiftUI

struct NovelDetailView: View {
    @Environment(BookSourceStore.self) private var sources
    @Environment(NovelShelfStore.self) private var shelf

    let book: NovelBook
    @State private var chapters: [NovelChapter] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var showReader = false
    @State private var readerStartIndex: Int = 0

    private var liveBook: NovelBook {
        shelf.books.first(where: { $0.id == book.id }) ?? book
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(liveBook.name)
                        .font(.title3.weight(.bold))
                    Text(liveBook.author.isEmpty ? "未知作者" : liveBook.author)
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
                        openReader(at: clampedProgressIndex)
                    } label: {
                        Label(continueLabel, systemImage: "book")
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
            } else if chapters.isEmpty {
                Section {
                    Text("暂无章节")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("目录 \(chapters.count) 章") {
                    // Use index as identity — never rely on chapter.url uniqueness alone.
                    ForEach(Array(chapters.enumerated()), id: \.offset) { index, ch in
                        Button {
                            openReader(at: index)
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
        .fullScreenCover(isPresented: $showReader) {
            // Re-inject environment: fullScreenCover can drop @Observable environments.
            NovelReaderView(
                book: liveBook,
                chapters: chapters,
                initialIndex: readerStartIndex
            )
            .environment(sources)
            .environment(shelf)
        }
    }

    private var clampedProgressIndex: Int {
        guard !chapters.isEmpty else { return 0 }
        return min(max(0, liveBook.lastChapterIndex), chapters.count - 1)
    }

    private var continueLabel: String {
        if liveBook.lastReadAt == nil {
            return "开始阅读"
        }
        let name = chapters[safe: clampedProgressIndex]?.name ?? ""
        return name.isEmpty ? "继续阅读" : "继续阅读 · \(name)"
    }

    private func openReader(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        readerStartIndex = index
        shelf.updateProgress(bookID: book.id, chapterIndex: index, offset: 0)
        showReader = true
    }

    private func loadChapters() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let source = sources.source(url: book.sourceURL)
            let list = try await NovelBookService.chapters(for: book, source: source)
            chapters = list
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
