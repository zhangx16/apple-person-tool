import Foundation

struct RSSFeedSource: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var url: String
    var enabled: Bool

    static let defaults: [RSSFeedSource] = [
        .init(id: "cls", title: "财联社电报", url: "https://pyrsshub.vercel.app/cls/telegraph/", enabled: true),
        .init(id: "hn", title: "Hacker News", url: "https://hnrss.org/frontpage", enabled: true),
        .init(id: "bbc", title: "BBC World", url: "https://feeds.bbci.co.uk/news/world/rss.xml", enabled: false)
    ]
}

struct RSSEntry: Identifiable, Hashable {
    var id: String
    var feedId: String
    var feedTitle: String
    var title: String
    var summary: String
    var link: String?
    var published: String
}

@MainActor
final class RSSStore: ObservableObject {
    static let shared = RSSStore()
    private let fileName = "rss_sources.json"

    @Published var sources: [RSSFeedSource] = []
    @Published private(set) var entries: [RSSEntry] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private init() {
        sources = LocalJSONStore.load([RSSFeedSource].self, from: fileName, fallback: RSSFeedSource.defaults)
        if sources.isEmpty { sources = RSSFeedSource.defaults }
    }

    private func persist() {
        LocalJSONStore.save(sources, to: fileName)
    }

    func addSource(title: String, url: String) {
        let item = RSSFeedSource(id: UUID().uuidString, title: title, url: url, enabled: true)
        sources.append(item)
        persist()
    }

    func removeSource(id: String) {
        sources.removeAll { $0.id == id }
        persist()
    }

    func toggle(_ id: String) {
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[i].enabled.toggle()
        persist()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var all: [RSSEntry] = []
        let enabled = sources.filter(\.enabled)
        await withTaskGroup(of: [RSSEntry].self) { group in
            for src in enabled {
                group.addTask { await self.fetchFeed(src) }
            }
            for await batch in group {
                all.append(contentsOf: batch)
            }
        }
        entries = all.sorted { $0.published > $1.published }
        if entries.isEmpty && !enabled.isEmpty {
            errorMessage = "未解析到条目，请检查订阅源 URL"
        }
    }

    private nonisolated func fetchFeed(_ src: RSSFeedSource) async -> [RSSEntry] {
        guard let url = URL(string: src.url) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.setValue("XIN's Tool RSS", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return Self.parseRSS(text, feed: src)
        } catch {
            return []
        }
    }

    private nonisolated static func parseRSS(_ xml: String, feed: RSSFeedSource) -> [RSSEntry] {
        // Lightweight tag scrape for item/entry
        let chunks = Array(xml.components(separatedBy: "<item").dropFirst())
            + Array(xml.components(separatedBy: "<entry").dropFirst())
        var out: [RSSEntry] = []
        for raw in chunks.prefix(40) {
            let block = raw
            let title = firstTag("title", in: block) ?? "(无标题)"
            let link = firstTag("link", in: block) ?? hrefLink(in: block)
            let desc = firstTag("description", in: block)
                ?? firstTag("summary", in: block)
                ?? firstTag("content", in: block)
                ?? ""
            let pub = firstTag("pubDate", in: block)
                ?? firstTag("updated", in: block)
                ?? firstTag("published", in: block)
                ?? ""
            let id = link ?? "\(feed.id)-\(title)-\(pub)"
            out.append(RSSEntry(
                id: id,
                feedId: feed.id,
                feedTitle: feed.title,
                title: stripHTML(title),
                summary: stripHTML(desc),
                link: link,
                published: pub
            ))
        }
        return out
    }

    private nonisolated static func firstTag(_ name: String, in block: String) -> String? {
        let patterns = [
            "<\(name)><!\\[CDATA\\[(.*?)\\]\\]></\(name)>",
            "<\(name)[^>]*>(.*?)</\(name)>"
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators, .caseInsensitive]),
               let m = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: block) {
                let s = String(block[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { return s }
            }
        }
        return nil
    }

    private nonisolated static func hrefLink(in block: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<link[^>]+href=["']([^"']+)["']"#, options: .caseInsensitive),
              let m = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: block) else { return nil }
        return String(block[r])
    }

    private nonisolated static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
