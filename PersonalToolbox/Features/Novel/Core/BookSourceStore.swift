import Foundation

@MainActor
@Observable
final class BookSourceStore {
    static let shared = BookSourceStore()

    private(set) var sources: [BookSource] = []
    private let fileURL: URL
    private let defaultsKey = "novel.bookSources.v1"
    private let seedVersionKey = "novel.bookSources.seedVersion"
    /// Bump when bundled default sources are refreshed (merges into existing store).
    private let currentSeedVersion = 5

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Novel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("book_sources.json")
        load()
    }

    var enabledSources: [BookSource] {
        sources.filter { $0.enabled != false }
    }

    var nativeEnabledSources: [BookSource] {
        enabledSources.filter(\.supportsNativeEngine)
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([BookSource].self, from: data),
           !list.isEmpty {
            sources = list
            migrateSeedIfNeeded()
            return
        }
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([BookSource].self, from: data),
           !list.isEmpty {
            sources = list
            persist()
            migrateSeedIfNeeded()
            return
        }
        // First launch: seed curated CSS/JSON sources.
        if seedBundledDefaults() {
            UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
            return
        }
        sources = []
    }

    /// Merge refreshed bundled sources; disable known-dead endpoints.
    private func migrateSeedIfNeeded() {
        let v = UserDefaults.standard.integer(forKey: seedVersionKey)
        guard v < currentSeedVersion else { return }
        _ = seedBundledDefaults()
        let deadHosts = [
            "www.dxmwx.org",
            "www.deqixs.com",
            "www.kuaishu5.com",
            "www.92xs.info"
        ]
        for i in sources.indices {
            if let host = URL(string: sources[i].bookSourceUrl)?.host,
               deadHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
                sources[i].enabled = false
            }
        }
        persist()
        UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
    }

    /// Load `Resources/Novel/default_book_sources.json` if present.
    @discardableResult
    func seedBundledDefaults() -> Bool {
        let candidates = [
            Bundle.main.url(forResource: "default_book_sources", withExtension: "json", subdirectory: "Novel"),
            Bundle.main.url(forResource: "default_book_sources", withExtension: "json", subdirectory: "Resources/Novel"),
            Bundle.main.url(forResource: "default_book_sources", withExtension: "json")
        ].compactMap { $0 }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let n = try? importJSONData(data), n >= 0 {
                return !sources.isEmpty
            }
        }
        return false
    }

    /// Recommended remote book-source packs (validated for availability).
    static let recommendedRemotePacks: [(name: String, url: String, note: String)] = [
        (
            "XIU2 自用书源（Bitbucket）",
            "https://bitbucket.org/xiu2/yuedu/raw/master/shuyuan",
            "约 26 条；约 5 条无 JS 可被本引擎搜索。网页打开乱码正常，APP 导入无影响。"
        ),
        (
            "XIU2 备用 CDN（jsd）",
            "https://jsd.onmicrosoft.cn/gh/XIU2/Yuedu/shuyuan",
            "与上同源；国内 CDN 分流。"
        ),
        (
            "XIU2 备用（GitHub raw）",
            "https://raw.githubusercontent.com/XIU2/Yuedu/master/shuyuan",
            "GitHub raw；网络受限时可能失败。"
        )
    ]

    /// Pull native-capable sources from Yiove public API (best-effort; API may 5xx).
    func importFromYiove(maxPages: Int = 5, pageSize: Int = 20) async throws -> Int {
        var collected: [BookSource] = []
        var seen = Set<String>()
        for page in 1...max(1, maxPages) {
            let listURL = URL(string: "https://shuyuan-api.yiove.com/shuyuan/book-sources?page=\(page)&page_size=\(pageSize)")!
            let (data, response) = try await URLSession.shared.data(from: listURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NovelError.network("Yiove HTTP \(http.statusCode)")
            }
            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let items = root["items"] as? [[String: Any]]
            else { break }

            for item in items {
                guard item["is_valid"] as? Bool != false,
                      let id = item["id"] as? String else { continue }
                let detailURL = URL(string: "https://shuyuan-api.yiove.com/shuyuan/book-source/\(id)")!
                do {
                    let (dData, _) = try await URLSession.shared.data(from: detailURL)
                    guard
                        let detail = try JSONSerialization.jsonObject(with: dData) as? [String: Any],
                        let origin = detail["origin_json"] as? String,
                        let oData = origin.data(using: .utf8)
                    else { continue }
                    let decoded = try JSONDecoder().decode(BookSource.self, from: oData)
                    guard decoded.supportsNativeEngine,
                          decoded.searchUrl != nil,
                          decoded.ruleSearch != nil,
                          seen.insert(decoded.bookSourceUrl).inserted
                    else { continue }
                    var s = decoded
                    if s.enabled == nil { s.enabled = true }
                    if let g = s.bookSourceGroup, !g.isEmpty {
                        s.bookSourceGroup = g + " · Yiove"
                    } else {
                        s.bookSourceGroup = "Yiove"
                    }
                    collected.append(s)
                } catch {
                    continue
                }
            }
            if items.isEmpty { break }
        }
        guard !collected.isEmpty else {
            throw NovelError.importFailed("Yiove 未拉到可用的 CSS/JSON 书源（接口可能繁忙）")
        }
        let data = try JSONEncoder().encode(collected)
        return try importJSONData(data)
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        try? data.write(to: fileURL, options: .atomic)
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    @discardableResult
    func importJSONData(_ data: Data) throws -> Int {
        let list = try Self.decodeSources(from: data)
        guard !list.isEmpty else { throw NovelError.importFailed("未解析到书源") }
        var map = Dictionary(uniqueKeysWithValues: sources.map { ($0.bookSourceUrl, $0) })
        var added = 0
        for var s in list {
            if s.enabled == nil { s.enabled = true }
            if map[s.bookSourceUrl] == nil { added += 1 }
            map[s.bookSourceUrl] = s
        }
        sources = map.values.sorted {
            ($0.customOrder ?? 0) < ($1.customOrder ?? 0)
                || (($0.customOrder ?? 0) == ($1.customOrder ?? 0)
                    && $0.bookSourceName.localizedStandardCompare($1.bookSourceName) == .orderedAscending)
        }
        persist()
        return added
    }

    func importJSONString(_ text: String) throws -> Int {
        guard let data = text.data(using: .utf8) else {
            throw NovelError.importFailed("文本编码错误")
        }
        return try importJSONData(data)
    }

    func importFromURL(_ urlString: String) async throws -> Int {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NovelError.badURL(urlString)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NovelError.network("HTTP \(http.statusCode)")
        }
        return try importJSONData(data)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == id }) else { return }
        sources[idx].enabled = enabled
        persist()
    }

    func delete(id: String) {
        sources.removeAll { $0.bookSourceUrl == id }
        persist()
    }

    func source(url: String) -> BookSource? {
        sources.first { $0.bookSourceUrl == url }
    }

    private static func decodeSources(from data: Data) throws -> [BookSource] {
        // Array
        if let list = try? JSONDecoder().decode([BookSource].self, from: data) {
            return list
        }
        // Single object
        if let one = try? JSONDecoder().decode(BookSource.self, from: data) {
            return [one]
        }
        // Sometimes double-encoded string
        if let str = String(data: data, encoding: .utf8),
           let inner = str.data(using: .utf8),
           let list = try? JSONDecoder().decode([BookSource].self, from: inner) {
            return list
        }
        throw NovelError.importFailed("JSON 格式不是书源数组/对象（需阅读/Legado 书源格式）")
    }
}
