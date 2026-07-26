import Foundation

enum TGChannelClientError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int, String)
    case decode
    case noPlayable

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "请先在设置中填写 TG 片库地址与 Token"
        case .badURL: return "服务地址无效"
        case .http(let c, let m): return "HTTP \(c)：\(m)"
        case .decode: return "响应解析失败"
        case .noPlayable: return "无可播放视频（可能只有外链）"
        }
    }
}

actor TGChannelClient {
    private let baseURL: String
    private let token: String
    private let session: URLSession

    init(baseURL: String, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    @MainActor
    static func fromSettings(_ s: AppSettings) throws -> TGChannelClient {
        let base = s.tgChannelBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = s.tgChannelToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !token.isEmpty else { throw TGChannelClientError.notConfigured }
        return TGChannelClient(baseURL: base, token: token)
    }

    func health() async throws -> TGHealth {
        try await get("/health", auth: false)
    }

    func channels() async throws -> [TGChannelInfo] {
        let res: TGChannelListResponse = try await get("/v1/channels")
        return res.items
    }

    func posts(
        username: String,
        limit: Int = 40,
        offset: Int = 0,
        videoOnly: Bool = false,
        query: String? = nil
    ) async throws -> TGPostListResponse {
        var q = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "video_only", value: videoOnly ? "true" : "false"),
        ]
        if let query, !query.isEmpty {
            q.append(URLQueryItem(name: "q", value: query))
        }
        return try await get("/v1/channels/\(username)/posts", query: q)
    }

    func triggerSync() async throws {
        let req = try makeRequest(path: "/v1/sync", method: "POST")
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
    }

    func cacheStats() async throws -> TGCacheStats {
        try await get("/v1/cache")
    }

    /// Delete server-side cached file for one post (frees VPS disk). Post stays in list.
    @discardableResult
    func deleteCache(postId: String) async throws -> TGCacheDeleteResult {
        let encoded = postId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? postId
        let req = try makeRequest(path: "/v1/posts/\(encoded)/cache", method: "DELETE")
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode(TGCacheDeleteResult.self, from: data)
    }

    /// Wipe all files under server media cache directory.
    @discardableResult
    func clearAllCache() async throws -> TGCacheDeleteResult {
        let req = try makeRequest(path: "/v1/cache", method: "DELETE")
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        return try JSONDecoder().decode(TGCacheDeleteResult.self, from: data)
    }

    /// Absolute play URL (with token as query is insecure; use header via AVURLAsset resource loader is complex).
    /// We download via URLRequest with Authorization into a temp file, or use cookie-less signed approach.
    /// For MVP: return URLRequest the player can use with header — AVPlayer needs AVURLAsset + resource loader
    /// or we download to temp. Simpler path: File stream URL with token query for personal use only.
    func playURL(for post: TGPost) throws -> URL {
        guard post.hasVideo, let path = post.playPath, !path.isEmpty else {
            throw TGChannelClientError.noPlayable
        }
        guard var comp = URLComponents(string: baseURL + path) else {
            throw TGChannelClientError.badURL
        }
        // Personal deploy: pass token as query so AVPlayer can open URL directly.
        // Prefer reverse-proxy basic auth or short-lived signed URLs in production.
        var items = comp.queryItems ?? []
        items.append(URLQueryItem(name: "token", value: token))
        comp.queryItems = items
        guard let url = comp.url else { throw TGChannelClientError.badURL }
        return url
    }

    func playRequest(for post: TGPost) throws -> URLRequest {
        guard post.hasVideo, let path = post.playPath, !path.isEmpty else {
            throw TGChannelClientError.noPlayable
        }
        var req = try makeRequest(path: path, method: "GET")
        // Play may wait for Telegram→server cache on first hit (multi‑GB).
        req.timeoutInterval = 600
        req.setValue("bytes=0-", forHTTPHeaderField: "Range")
        req.setValue("video/*,*/*", forHTTPHeaderField: "Accept")
        return req
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], auth: Bool = true) async throws -> T {
        let req = try makeRequest(path: path, method: "GET", query: query, auth: auth)
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TGChannelClientError.decode
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        auth: Bool = true
    ) throws -> URLRequest {
        let p = path.hasPrefix("/") ? path : "/" + path
        guard var comp = URLComponents(string: baseURL + p) else {
            throw TGChannelClientError.badURL
        }
        if !query.isEmpty {
            comp.queryItems = (comp.queryItems ?? []) + query
        }
        guard let url = comp.url else { throw TGChannelClientError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(token, forHTTPHeaderField: "X-Api-Token")
        }
        return req
    }

    private func validate(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw TGChannelClientError.http(http.statusCode, String(msg.prefix(200)))
        }
    }
}
