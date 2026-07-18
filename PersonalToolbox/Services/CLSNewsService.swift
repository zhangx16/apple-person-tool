import Foundation

/// 财联社电报 RSS 拉取 + 磁盘缓存（对齐 财联社.scripting）。
actor CLSNewsService {
    static let shared = CLSNewsService()

    private let cacheFileName = "cls_telegraph_cache.json"
    /// Prefer fresh within 5 minutes.
    private let softTTL: TimeInterval = 5 * 60
    /// Fallback max age 24 hours.
    private let hardTTL: TimeInterval = 24 * 60 * 60

    private var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
    }

    struct FetchResult: Sendable {
        var items: [CLSNewsItem]
        var fromCache: Bool
        var lastUpdated: Date?
        var errorMessage: String?
    }

    func fetch(feedURL: String, forceRefresh: Bool = false) async -> FetchResult {
        let urlString = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = urlString.isEmpty ? CLSNewsParsing.defaultFeedURL : urlString

        if !forceRefresh, let cache = loadCache(), cache.sourceURL == effective {
            let age = Date().timeIntervalSince(cache.lastUpdated)
            if age < softTTL, !cache.items.isEmpty {
                return FetchResult(items: cache.items, fromCache: true, lastUpdated: cache.lastUpdated, errorMessage: nil)
            }
        }

        do {
            let items = try await downloadAndParse(urlString: effective)
            if !items.isEmpty {
                let cache = CLSNewsCache(items: items, lastUpdated: Date(), sourceURL: effective)
                saveCache(cache)
                return FetchResult(items: items, fromCache: false, lastUpdated: cache.lastUpdated, errorMessage: nil)
            }
            throw NetworkError.message("RSS 解析为空")
        } catch {
            if let cache = loadCache(), !cache.items.isEmpty {
                let age = Date().timeIntervalSince(cache.lastUpdated)
                if age < hardTTL {
                    return FetchResult(
                        items: cache.items,
                        fromCache: true,
                        lastUpdated: cache.lastUpdated,
                        errorMessage: error.localizedDescription
                    )
                }
            }
            return FetchResult(
                items: [],
                fromCache: false,
                lastUpdated: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: - Network

    private func downloadAndParse(urlString: String) async throws -> [CLSNewsItem] {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/rss+xml, application/atom+xml, text/xml, */*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16) else {
            throw NetworkError.message("无法解码 RSS 文本")
        }
        let items = CLSNewsParsing.parseFeedXML(text)
        if items.isEmpty {
            throw NetworkError.message("RSS 解析失败")
        }
        return items
    }

    // MARK: - Cache IO

    private func loadCache() -> CLSNewsCache? {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CLSNewsCache.self, from: data) else {
            return nil
        }
        return cache
    }

    private func saveCache(_ cache: CLSNewsCache) {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: [.atomic])
        } catch {}
    }
}
