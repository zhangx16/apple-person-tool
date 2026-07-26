import Foundation

/// Legado-compatible book source (subset used by 开源阅读).
/// See https://github.com/gedoor/legado and docs on gedoor.github.io
struct BookSource: Codable, Identifiable, Hashable, Sendable {
    var id: String { bookSourceUrl }
    var bookSourceName: String
    var bookSourceUrl: String
    var bookSourceType: Int?
    var bookSourceGroup: String?
    var bookSourceComment: String?
    var enabled: Bool?
    var enabledExplore: Bool?
    var searchUrl: String?
    var exploreUrl: String?
    var header: String?
    var loginUrl: String?
    var bookUrlPattern: String?
    var weight: Int?
    var customOrder: Int?
    var lastUpdateTime: Int64?
    var ruleSearch: BookRuleSearch?
    var ruleBookInfo: BookRuleBookInfo?
    var ruleToc: BookRuleToc?
    var ruleContent: BookRuleContent?
    var ruleExplore: BookRuleExplore?

    /// Soft check: heavy JS sources are imported but marked limited.
    var supportsNativeEngine: Bool {
        let blob = [
            searchUrl,
            ruleSearch?.bookList, ruleSearch?.name, ruleSearch?.bookUrl,
            ruleToc?.chapterList, ruleContent?.content
        ].compactMap { $0 }.joined()
        let lower = blob.lowercased()
        if lower.contains("<js>") || lower.contains("@js") || lower.contains("java.") {
            return false
        }
        return true
    }
}

struct BookRuleSearch: Codable, Hashable, Sendable {
    var bookList: String?
    var name: String?
    var author: String?
    var kind: String?
    var wordCount: String?
    var lastChapter: String?
    var intro: String?
    var coverUrl: String?
    var bookUrl: String?
    var checkKeyWord: String?
}

struct BookRuleBookInfo: Codable, Hashable, Sendable {
    var initRule: String?
    var name: String?
    var author: String?
    var kind: String?
    var wordCount: String?
    var lastChapter: String?
    var intro: String?
    var coverUrl: String?
    var tocUrl: String?

    enum CodingKeys: String, CodingKey {
        case initRule = "init"
        case name, author, kind, wordCount, lastChapter, intro, coverUrl, tocUrl
    }
}

struct BookRuleToc: Codable, Hashable, Sendable {
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var updateTime: String?
    var nextTocUrl: String?
    var isVolume: String?
}

struct BookRuleContent: Codable, Hashable, Sendable {
    var content: String?
    var nextContentUrl: String?
    var replaceRegex: String?
    var sourceRegex: String?
}

struct BookRuleExplore: Codable, Hashable, Sendable {
    var bookList: String?
    var name: String?
    var author: String?
    var kind: String?
    var coverUrl: String?
    var bookUrl: String?
    var intro: String?
    var lastChapter: String?
}

// MARK: - Domain models

struct NovelBook: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var author: String
    var coverURL: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var wordCount: String?
    /// Absolute book page URL (or local file://)
    var bookURL: String
    var sourceURL: String
    var sourceName: String
    var isLocal: Bool
    var localFileName: String?
    var addedAt: Date
    var lastReadAt: Date?
    var lastChapterIndex: Int
    var lastReadOffset: Double

    static func makeID(sourceURL: String, bookURL: String) -> String {
        "\(sourceURL)|\(bookURL)"
    }
}

struct NovelChapter: Identifiable, Hashable, Sendable {
    /// Stable unique id (must be unique within a TOC — empty href used to collide and crash ForEach).
    var id: String
    var name: String
    var url: String

    init(name: String, url: String, id: String? = nil) {
        self.name = name
        self.url = url
        if let id, !id.isEmpty {
            self.id = id
        } else if !url.isEmpty {
            self.id = url
        } else {
            self.id = "ch-\(name)"
        }
    }
}

struct NovelSearchHit: Identifiable, Hashable, Sendable {
    var id: String { "\(sourceURL)|\(bookURL)|\(name)" }
    var name: String
    var author: String
    var coverURL: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var bookURL: String
    var sourceURL: String
    var sourceName: String
}
