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
    /// Upstream expects `credentials` + `password`, and `client=webgui` (login is webgui-restricted).
    func login(baseURL: String, username: String, password: String) async throws -> String {
        let payload: [String: Any] = [
            "credentials": username,
            "password": password
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http) = try await client.data(
            base: normalizeBase(baseURL),
            path: "/api/user/login",
            method: "POST",
            headers: headers(token: nil),
            body: body,
            query: [
                .init(name: "client", value: "webgui"),
                .init(name: "lang", value: "zh-CN")
            ]
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // status:false → business error
            if let status = obj["status"] as? Bool, status == false {
                let msg = (obj["message"] as? String) ?? "登录失败"
                let details = (obj["details"] as? String).map { " (\($0))" } ?? ""
                throw NetworkError.message(msg + details)
            }
            if let token = obj["data"] as? String, !token.isEmpty { return token }
            if let dataObj = obj["data"] as? [String: Any] {
                if let token = dataObj["token"] as? String, !token.isEmpty { return token }
                if let token = dataObj["Token"] as? String, !token.isEmpty { return token }
            }
            if let token = obj["token"] as? String, !token.isEmpty { return token }
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

    // MARK: Folders & attachments

    struct FolderNode: Identifiable, Hashable {
        var id: String { path }
        var path: String
        var name: String
        /// `nil` = leaf (required by `OutlineGroup`).
        var children: [FolderNode]?
    }

    struct AttachmentItem: Identifiable, Hashable {
        var id: String { path }
        var path: String
        var name: String
        var size: Int?
    }

    func folderTree(baseURL: String, token: String) async throws -> [FolderNode] {
        let (data, http) = try await client.data(
            base: normalizeBase(baseURL),
            path: "/api/folder/tree",
            method: "GET",
            headers: headers(token: token)
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let root = obj["data"]
        return parseFolderNodes(root, parentPath: "")
    }

    func notesInFolder(baseURL: String, token: String, path: String, page: Int = 1) async throws -> [NoteListItem] {
        let (data, http) = try await client.data(
            base: normalizeBase(baseURL),
            path: "/api/folder/notes",
            method: "GET",
            headers: headers(token: token),
            query: [
                .init(name: "path", value: path),
                .init(name: "page", value: "\(page)"),
                .init(name: "page_size", value: "50")
            ]
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        return parseNoteList(data)
    }

    func filesInFolder(baseURL: String, token: String, path: String) async throws -> [AttachmentItem] {
        let (data, http) = try await client.data(
            base: normalizeBase(baseURL),
            path: "/api/folder/files",
            method: "GET",
            headers: headers(token: token),
            query: [
                .init(name: "path", value: path),
                .init(name: "page", value: "1"),
                .init(name: "page_size", value: "50")
            ]
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var listAny: [[String: Any]] = []
        if let arr = obj["data"] as? [[String: Any]] {
            listAny = arr
        } else if let d = obj["data"] as? [String: Any], let arr = d["list"] as? [[String: Any]] {
            listAny = arr
        }
        return listAny.compactMap { dict in
            let p = (dict["path"] as? String) ?? (dict["Path"] as? String) ?? ""
            guard !p.isEmpty else { return nil }
            let name = (dict["name"] as? String) ?? (p as NSString).lastPathComponent
            let size = dict["size"] as? Int
            return AttachmentItem(path: p, name: name, size: size)
        }
    }

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
        // data may be array of folders or nested { name, path, children }
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
        if path.isEmpty && name.isEmpty {
            return children
        }
        if name.isEmpty && !children.isEmpty {
            return children
        }
        return [
            FolderNode(
                path: path,
                name: name.isEmpty ? path : name,
                children: children.isEmpty ? nil : children
            )
        ]
    }
}
