import Foundation

/// Client for haierkeys/fast-note-sync-service REST API.
///
/// Auth findings (this deployment):
/// - Login **must** use query `client=webgui` + JSON body `{credentials,password}`
///   otherwise server returns code 314 "Auth token Client restricted".
/// - Subsequent APIs accept header `token: <jwt>` or `Authorization: Bearer <jwt>`.
/// - Note list requires `vault` (e.g. `zxin`).
actor FastNoteSyncService {
    static let shared = FastNoteSyncService()

    /// Server binds JWT to User-Agent. All Fast Note requests **must** share this exact string
    /// or later calls fail with "Auth token Browser (UA) restricted (User-Agent mismatch)".
    private static let fixedUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

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
            case pathHashCamel = "pathHash"
            case updatedAt = "updated_at"
            case updatedAtCamel = "updatedAt"
            case mtime
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decodeIfPresent(String.self, forKey: .path)
            pathHash = (try? c.decodeIfPresent(String.self, forKey: .pathHash))
                ?? (try? c.decodeIfPresent(String.self, forKey: .pathHashCamel))
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
            if let p = path, !p.isEmpty { return (p as NSString).lastPathComponent }
            return "未命名笔记"
        }
    }

    struct FolderNode: Identifiable, Hashable {
        var id: String { path }
        var path: String
        var name: String
        var children: [FolderNode]?
    }

    struct AttachmentItem: Identifiable, Hashable {
        var id: String { path }
        var path: String
        var name: String
        var size: Int?
    }

    private func normalizeBase(_ base: String) -> String {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        // Users sometimes paste the webgui URL; strip it for API base.
        if b.hasSuffix("/webgui") { b = String(b.dropLast("/webgui".count)) }
        if b.hasSuffix("/webgui/") { b = String(b.dropLast("/webgui/".count)) }
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    private func authHeaders(token: String?) -> [String: String] {
        var h: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            // Must match login UA for the lifetime of the token.
            "User-Agent": Self.fixedUserAgent
        ]
        if let token, !token.isEmpty {
            // Both forms observed working on this deployment.
            h["token"] = token
            h["Authorization"] = "Bearer \(token)"
        }
        return h
    }

    /// Dedicated session so iOS does not inject a different default User-Agent.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "User-Agent": FastNoteSyncService.fixedUserAgent
        ]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    /// Low-level request that always builds URL with query items.
    private func request(
        baseURL: String,
        path: String,
        method: String,
        token: String? = nil,
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let base = normalizeBase(baseURL)
        guard var comps = URLComponents(string: base + (path.hasPrefix("/") ? path : "/" + path)) else {
            throw NetworkError.invalidURL
        }
        if !query.isEmpty {
            comps.queryItems = (comps.queryItems ?? []) + query
        }
        guard let url = comps.url else { throw NetworkError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.timeoutInterval = 30
        for (k, v) in authHeaders(token: token) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        // Explicit again — some iOS versions override request UA from session.
        req.setValue(Self.fixedUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        return (data, http)
    }

    private func parseBusinessError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let status = obj["status"] as? Bool, status == false {
            let msg = (obj["message"] as? String) ?? "请求失败"
            if let details = obj["details"] as? String, !details.isEmpty {
                return "\(msg)（\(details)）"
            }
            if let dataStr = obj["data"] as? String, !dataStr.isEmpty {
                return "\(msg)（\(dataStr)）"
            }
            return msg
        }
        return nil
    }

    // MARK: - Login

    /// Login → JWT string.
    /// Critical: `client=webgui` **must** be on the query string or server returns 314 Client restricted.
    func login(baseURL: String, username: String, password: String) async throws -> String {
        let cred = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password
        guard !cred.isEmpty, !pass.isEmpty else {
            throw NetworkError.message("请填写用户名和密码")
        }

        let payload: [String: Any] = [
            "credentials": cred,
            "password": pass
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        // Build URL with client in the string so it cannot be dropped.
        let base = normalizeBase(baseURL)
        guard let url = URL(string: base + "/api/user/login?client=webgui&lang=zh-CN") else {
            throw NetworkError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Same UA as all subsequent note API calls (token is UA-bound).
        req.setValue(Self.fixedUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetworkError.invalidResponse }

        if let biz = parseBusinessError(data) {
            throw NetworkError.message(biz)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }

        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let dataObj = obj["data"] as? [String: Any] {
                if let token = dataObj["token"] as? String, !token.isEmpty { return token }
            }
            if let token = obj["data"] as? String, !token.isEmpty { return token }
            if let token = obj["token"] as? String, !token.isEmpty { return token }
        }
        throw NetworkError.message("登录成功但未返回 token")
    }

    // MARK: - Notes

    func listNotes(
        baseURL: String,
        token: String,
        vault: String,
        page: Int = 1,
        pageSize: Int = 50
    ) async throws -> [NoteListItem] {
        let vaultName = vault.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vaultName.isEmpty else { throw NetworkError.message("请填写仓库名 vault（如 zxin）") }

        let (data, http) = try await request(
            baseURL: baseURL,
            path: "/api/notes",
            method: "GET",
            token: token,
            query: [
                .init(name: "vault", value: vaultName),
                .init(name: "page", value: "\(page)"),
                .init(name: "page_size", value: "\(pageSize)"),
                .init(name: "pageSize", value: "\(pageSize)")
            ]
        )
        if let biz = parseBusinessError(data) { throw NetworkError.message(biz) }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        return parseNoteList(data)
    }

    func getNote(baseURL: String, token: String, vault: String, path: String) async throws -> String {
        let (data, http) = try await request(
            baseURL: baseURL,
            path: "/api/note",
            method: "GET",
            token: token,
            query: [
                .init(name: "vault", value: vault),
                .init(name: "path", value: path)
            ]
        )
        if let biz = parseBusinessError(data) { throw NetworkError.message(biz) }
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

    /// Create a new markdown note under the vault root (or folder path).
    func createNote(
        baseURL: String,
        token: String,
        vault: String,
        folder: String = "",
        title: String
    ) async throws -> String {
        let safe = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let name = safe.isEmpty ? "新笔记-\(Int(Date().timeIntervalSince1970))" : safe
        let file = name.hasSuffix(".md") ? name : "\(name).md"
        let folderTrim = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = folderTrim.isEmpty ? file : "\(folderTrim)/\(file)"
        let body = "# \(name.replacingOccurrences(of: ".md", with: ""))\n\n"
        try await saveNote(baseURL: baseURL, token: token, vault: vault, path: path, content: body)
        return path
    }

    func saveNote(baseURL: String, token: String, vault: String, path: String, content: String) async throws {
        let payload: [String: Any] = [
            "vault": vault,
            "path": path,
            "content": content
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http) = try await request(
            baseURL: baseURL,
            path: "/api/note",
            method: "POST",
            token: token,
            body: body
        )
        if let biz = parseBusinessError(data) { throw NetworkError.message(biz) }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
    }

    func folderTree(baseURL: String, token: String, vault: String) async throws -> [FolderNode] {
        let (data, http) = try await request(
            baseURL: baseURL,
            path: "/api/folder/tree",
            method: "GET",
            token: token,
            query: [.init(name: "vault", value: vault)]
        )
        if let biz = parseBusinessError(data) {
            // Folder APIs may be optional — return empty instead of failing list
            if biz.contains("Not Found") { return [] }
            throw NetworkError.message(biz)
        }
        guard (200..<300).contains(http.statusCode) else { return [] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return parseFolderNodes(obj["data"], parentPath: "")
    }

    func notesInFolder(baseURL: String, token: String, vault: String, path: String, page: Int = 1) async throws -> [NoteListItem] {
        let (data, http) = try await request(
            baseURL: baseURL,
            path: "/api/folder/notes",
            method: "GET",
            token: token,
            query: [
                .init(name: "vault", value: vault),
                .init(name: "path", value: path),
                .init(name: "page", value: "\(page)"),
                .init(name: "page_size", value: "50")
            ]
        )
        if let biz = parseBusinessError(data) { throw NetworkError.message(biz) }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        return parseNoteList(data)
    }

    func filesInFolder(baseURL: String, token: String, vault: String, path: String) async throws -> [AttachmentItem] {
        let (data, http) = try await request(
            baseURL: baseURL,
            path: "/api/folder/files",
            method: "GET",
            token: token,
            query: [
                .init(name: "vault", value: vault),
                .init(name: "path", value: path),
                .init(name: "page", value: "1"),
                .init(name: "page_size", value: "50")
            ]
        )
        if let biz = parseBusinessError(data) {
            if biz.contains("Not Found") || biz.contains("Not logged") { return [] }
            throw NetworkError.message(biz)
        }
        guard (200..<300).contains(http.statusCode) else { return [] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var listAny: [[String: Any]] = []
        if let arr = obj["data"] as? [[String: Any]] {
            listAny = arr
        } else if let d = obj["data"] as? [String: Any], let arr = d["list"] as? [[String: Any]] {
            listAny = arr
        }
        return listAny.compactMap { dict in
            let p = (dict["path"] as? String) ?? ""
            guard !p.isEmpty else { return nil }
            let name = (dict["name"] as? String) ?? (p as NSString).lastPathComponent
            return AttachmentItem(path: p, name: name, size: dict["size"] as? Int)
        }
    }

    // MARK: - Parse helpers

    private func parseNoteList(_ data: Data) -> [NoteListItem] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
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

    private func parseFolderNodes(_ node: Any?, parentPath: String) -> [FolderNode] {
        guard let node else { return [] }
        if let arr = node as? [Any] {
            return arr.flatMap { parseFolderNodes($0, parentPath: parentPath) }
        }
        guard let dict = node as? [String: Any] else { return [] }
        let name = (dict["name"] as? String) ?? (dict["Name"] as? String) ?? ""
        var path = (dict["path"] as? String) ?? (dict["Path"] as? String) ?? ""
        if path.isEmpty, !name.isEmpty {
            path = parentPath.isEmpty ? name : parentPath + "/" + name
        }
        let childrenRaw = dict["children"] ?? dict["Children"] ?? dict["folders"]
        let children = parseFolderNodes(childrenRaw, parentPath: path)
        if path.isEmpty && name.isEmpty { return children }
        if name.isEmpty && !children.isEmpty { return children }
        return [
            FolderNode(
                path: path,
                name: name.isEmpty ? path : name,
                children: children.isEmpty ? nil : children
            )
        ]
    }
}
