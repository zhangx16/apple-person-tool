import Foundation

@MainActor
@Observable
final class NovelShelfStore {
    static let shared = NovelShelfStore()

    private(set) var books: [NovelBook] = []
    private let fileURL: URL
    private let textsDir: URL

    private init() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Novel", isDirectory: true)
        textsDir = root.appendingPathComponent("LocalTexts", isDirectory: true)
        try? FileManager.default.createDirectory(at: textsDir, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("shelf.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([NovelBook].self, from: data) else {
            books = []
            return
        }
        books = list.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    func addFromSearch(_ hit: NovelSearchHit) -> NovelBook {
        let id = NovelBook.makeID(sourceURL: hit.sourceURL, bookURL: hit.bookURL)
        if let existing = books.first(where: { $0.id == id }) {
            return existing
        }
        let book = NovelBook(
            id: id,
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
        books.insert(book, at: 0)
        persist()
        return book
    }

    @discardableResult
    func importLocalTXT(fileName: String, content: String, title: String?, author: String?) throws -> NovelBook {
        let safe = fileName
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = "\(Int(Date().timeIntervalSince1970))_\(safe)"
        let url = textsDir.appendingPathComponent(stored)
        guard let data = content.data(using: .utf8) else {
            throw NovelError.importFailed("无法写入文件")
        }
        try data.write(to: url, options: .atomic)
        let name = title?.isEmpty == false ? title! : (safe as NSString).deletingPathExtension
        let book = NovelBook(
            id: "local|\(stored)",
            name: name,
            author: author?.isEmpty == false ? author! : "本地",
            coverURL: nil,
            intro: "本地导入 · \(content.count) 字",
            kind: "本地",
            lastChapter: nil,
            wordCount: "\(content.count)",
            bookURL: url.absoluteString,
            sourceURL: "local",
            sourceName: "本地TXT",
            isLocal: true,
            localFileName: stored,
            addedAt: Date(),
            lastReadAt: nil,
            lastChapterIndex: 0,
            lastReadOffset: 0
        )
        books.insert(book, at: 0)
        persist()
        return book
    }

    func localText(for book: NovelBook) -> String? {
        guard book.isLocal, let name = book.localFileName else { return nil }
        let url = textsDir.appendingPathComponent(name)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func updateProgress(bookID: String, chapterIndex: Int, offset: Double) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].lastChapterIndex = max(0, chapterIndex)
        books[idx].lastReadOffset = offset
        books[idx].lastReadAt = Date()
        persist()
        // keep sorted
        books.sort { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
    }

    func remove(bookID: String) {
        if let book = books.first(where: { $0.id == bookID }),
           book.isLocal, let name = book.localFileName {
            let url = textsDir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
        books.removeAll { $0.id == bookID }
        persist()
    }
}
