import Foundation

/// Client for haierkeys/fast-note-sync-service REST API.
/// Docs: https://github.com/haierkeys/fast-note-sync-service/blob/master/docs/REST_API.md
/// Auth header: `Authorization: {token}` (no Bearer prefix per upstream docs).
actor FastNoteSyncService {
    static let shared = FastNoteSyncService()
    private let client = NetworkClient.shared

    struct LoginResult: Decodable {
        var token: String?
        // some deployments nest token under data
    }

    struct NoteListItem: Codable, Identifiable, Hashable {
        var id: String { path ?? pathHash ?? UUID().uuidString }
        var path: String?
        var pathHash: String?
        var title: String?
        var updatedAt: String?
        var size: Int?

        enum CodingKeys: String, CodingKey {
            case path, title, size
            case pathHash = "path_hash"
            case updatedAt = "updated_at"
            case updatedAtCamel = "updatedAt"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decodeIfPresent(String.self, forKey: .path)
            pathHash = try c.decodeIfPresent(String.self, forKey: .pathHash)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            size = try c.decodeIfPresent(Int.self, forKey: .size)
            updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt))
                ?? (try? c.decodeIfPresent(String.self, forKey: .updatedAtCamel))
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(path, forKey: .path)
            try c.encodeIfPresent(pathHash, forKey: .pathHash)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encodeIfPresent(size, forKey: .size)
            try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        }

        var displayTitle: String {
            if let t = title, !t.isEmpty { return t }
            if let p = path, !p.isEmpty {
                return (p as NSString).lastPathComponent
            }
            return "未命名笔记"
        }
    }

    private func headers(token: String?) -> [String: String] {
        var h = ["Content-Type": "application/json", "Accept": "application/json"]
        if let token, !token.isEmpty {
            // Upstream docs: Authorization: {token} (not Bearer)
            h["Authorization"] = token
            h["token"] = token
        }
        return h
    }

    private func normalizeBase(_ base: String) -> String {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    /// Login → token string.
    func login(baseURL: String, username: String, password: String) async throws -> String {
        let body = try JSONEncoder().encode([
            "username": username,
            "password": password
        ])
        // Some deployments expect nested params
        let body2 = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password
        ])
        _ = body2
        let (data, http) = try await client.data(
            base: normalizeBase(baseURL),
            path: "/api/user/login",
            method: "POST",
            headers: headers(token: nil),
            body: body
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let token = obj["data"] as? String, !token.isEmpty { return token }
            if let dataObj = obj["data"] as? [String: Any] {
                if let token = dataObj["token"] as? String, !token.isEmpty { return token }
                if let token = dataObj["Token"] as? String, !token.isEmpty { return token }
            }
            if let token = obj["token"] as? String, !token.isEmpty { return token }
            if let msg = obj["message"] as? String, obj["status"] as? Bool == false {
                throw NetworkError.message(msg)
            }
        }
        throw NetworkError.message("登录成功但未返回 token")
    }

    func listNotes(baseURL: String, token: String, page: Int = 1, pageSize: Int = 50) async throws -> [NoteListItem] {
        let (data, http) = try await client.data(
            base: normalizeBase(baseURL),
            path: "/api/notes",
            method: "GET",
            headers: headers(token: token),
            query: [
                .init(name: "page", value: "\(page)"),
                .init(name: "page_size", value: "\(pageSize)")
            ]
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        // Flexible parse
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let payload = obj["data"]
            var listAny: [[String: Any]] = []
            if let arr = payload as? [[String: Any]] {
                listAny = arr
            } else if let dict = payload as? [String: Any], let arr = dict["list"] as? [[String: Any]] {
                listAny = arr
            }
            return listAny.compactMap { dict in
                guard let raw = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                return try? JSONDecoder().decode(NoteListItem.self, from: raw)
            }
        }
        return []
    }

    func getNote(baseURL: String, token: String, path: String) async throws -> String {
        let (data, http) = try await client.data(
            base: normalizeBase(baseURL),
            path: "/api/note",
            method: "GET",
            headers: headers(token: token),
            query: [.init(name: "path", value: path)]
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = obj["data"] as? String { return s }
            if let d = obj["data"] as? [String: Any] {
                if let c = d["content"] as? String { return c }
                if let c = d["Content"] as? String { return c }
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func saveNote(baseURL: String, token: String, path: String, content: String) async throws {
        let payload: [String: Any] = ["path": path, "content": content]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http) = try await client.data(
            base: normalizeBase(baseURL),
            path: "/api/note",
            method: "POST",
            headers: headers(token: token),
            body: body
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = obj["status"] as? Bool, status == false {
            throw NetworkError.message((obj["message"] as? String) ?? "保存失败")
        }
    }
}
