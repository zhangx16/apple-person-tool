import SwiftUI

struct NovelReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BookSourceStore.self) private var sources
    @Environment(NovelShelfStore.self) private var shelf

    let book: NovelBook
    let chapters: [NovelChapter]
    let initialIndex: Int

    @State private var chapterIndex: Int = 0
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var error: String?
    @State private var fontSize: Double = UserDefaults.standard.object(forKey: "novel.reader.fontSize") as? Double ?? 19
    @State private var themeRaw: String = UserDefaults.standard.string(forKey: "novel.reader.theme") ?? ReaderTheme.sepia.rawValue
    @State private var showChrome = true
    @State private var showToc = false

    private var theme: ReaderTheme {
        ReaderTheme(rawValue: themeRaw) ?? .sepia
    }

    private var source: BookSource? { sources.source(url: book.sourceURL) }

    private var safeIndex: Int {
        guard !chapters.isEmpty else { return 0 }
        return min(max(0, chapterIndex), chapters.count - 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()
                if chapters.isEmpty {
                    ContentUnavailableView("无章节", systemImage: "book.closed", description: Text("目录为空，无法阅读"))
                } else if isLoading {
                    ProgressView("加载正文…")
                } else if let error {
                    VStack(spacing: 12) {
                        ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                        Button("重试") { Task { await loadContent() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(chapters[safe: safeIndex]?.name ?? "")
                                .font(.headline)
                                .foregroundStyle(theme.secondary)
                            Text(content.isEmpty ? "（本章无正文）" : content)
                                .font(.system(size: fontSize))
                                .foregroundStyle(theme.foreground)
                                .lineSpacing(fontSize * 0.45)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                    .onTapGesture { withAnimation { showChrome.toggle() } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showChrome, !chapters.isEmpty {
                    controlBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        persistProgress()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(book.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showToc = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .disabled(chapters.isEmpty)
                }
            }
            .toolbar(showChrome ? .visible : .hidden, for: .navigationBar)
            .sheet(isPresented: $showToc) {
                NavigationStack {
                    List {
                        ForEach(Array(chapters.enumerated()), id: \.offset) { i, ch in
                            Button {
                                chapterIndex = i
                                showToc = false
                                Task { await loadContent() }
                            } label: {
                                HStack {
                                    Text(ch.name)
                                        .foregroundStyle(.primary)
                                    if i == safeIndex {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("目录")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showToc = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .environment(sources)
                .environment(shelf)
            }
        }
        .task {
            if chapters.isEmpty {
                isLoading = false
                error = "目录为空"
                return
            }
            chapterIndex = min(max(0, initialIndex), chapters.count - 1)
            await loadContent()
        }
        .onChange(of: fontSize) { _, v in
            UserDefaults.standard.set(v, forKey: "novel.reader.fontSize")
        }
        .onChange(of: themeRaw) { _, v in
            UserDefaults.standard.set(v, forKey: "novel.reader.theme")
        }
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    guard safeIndex > 0 else { return }
                    chapterIndex = safeIndex - 1
                    Task { await loadContent() }
                } label: {
                    Label("上一章", systemImage: "chevron.left")
                }
                .disabled(safeIndex <= 0)

                Spacer()

                Menu {
                    Picker("主题", selection: $themeRaw) {
                        ForEach(ReaderTheme.allCases) { t in
                            Text(t.title).tag(t.rawValue)
                        }
                    }
                    Slider(value: $fontSize, in: 14...30, step: 1) {
                        Text("字号")
                    }
                } label: {
                    Image(systemName: "textformat.size")
                }

                Spacer()

                Button {
                    guard safeIndex + 1 < chapters.count else { return }
                    chapterIndex = safeIndex + 1
                    Task { await loadContent() }
                } label: {
                    Label("下一章", systemImage: "chevron.right")
                }
                .disabled(safeIndex + 1 >= chapters.count)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func loadContent() async {
        guard chapters.indices.contains(safeIndex) else {
            isLoading = false
            error = "章节无效"
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        let ch = chapters[safeIndex]
        do {
            content = try await NovelBookService.content(
                chapter: ch,
                book: book,
                source: source,
                allLocalChapters: chapters
            )
            persistProgress()
        } catch {
            self.error = error.localizedDescription
            content = ""
        }
    }

    private func persistProgress() {
        guard !chapters.isEmpty else { return }
        shelf.updateProgress(bookID: book.id, chapterIndex: safeIndex, offset: 0)
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper
    case sepia
    case night
    case green

    var id: String { rawValue }
    var title: String {
        switch self {
        case .paper: "白纸"
        case .sepia: "羊皮"
        case .night: "夜间"
        case .green: "护眼"
        }
    }

    var background: Color {
        switch self {
        case .paper: Color(uiColor: .systemBackground)
        case .sepia: Color(red: 0.96, green: 0.93, blue: 0.84)
        case .night: Color(red: 0.10, green: 0.10, blue: 0.12)
        case .green: Color(red: 0.85, green: 0.93, blue: 0.85)
        }
    }

    var foreground: Color {
        switch self {
        case .night: Color(white: 0.85)
        default: Color.primary
        }
    }

    var secondary: Color {
        switch self {
        case .night: Color(white: 0.6)
        default: Color.secondary
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
