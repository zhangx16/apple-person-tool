import Foundation

/// SublinkX (sublinkx-app) admin API client.
/// Base: https://sub.996616.xyz — JWT Bearer after form login with captcha.
/// Write endpoints mostly use `application/x-www-form-urlencoded` (same as web multipart fields);
/// bulk import uses JSON.
actor SublinkService {
    static let shared = SublinkService()
    private let client = NetworkClient.shared
    private var token: String?

    func logout() {
        token = nil
        KeychainStore.delete("sublinkAccessToken")
    }

    func restoreToken() {
        if token != nil { return }
        if let t = KeychainStore.get("sublinkAccessToken"), !t.isEmpty {
            token = t
        }
    }

    var hasToken: Bool {
        if token != nil { return true }
        if let t = KeychainStore.get("sublinkAccessToken"), !t.isEmpty { return true }
        return false
    }

    private func saveToken(_ t: String) {
        token = t
        KeychainStore.set(t, for: "sublinkAccessToken")
    }

    private func authHeaders(extra: [String: String] = [:]) throws -> [String: String] {
        guard let token, !token.isEmpty else { throw NetworkError.unauthorized }
        var h: [String: String] = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json"
        ]
        for (k, v) in extra { h[k] = v }
        return h
    }

    // MARK: - Auth

    func fetchCaptcha(baseURL: String) async throws -> SublinkCaptcha {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/v1/auth/captcha",
            headers: ["Accept": "application/json"]
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        let env = try JSONDecoder().decode(SublinkEnvelope<SublinkCaptcha>.self, from: data)
        guard env.isSuccess, let cap = env.data else {
            throw NetworkError.message(env.errorText)
        }
        return cap
    }

    /// Login uses `application/x-www-form-urlencoded` fields (not JSON).
    func login(
        baseURL: String,
        username: String,
        password: String,
        captchaCode: String,
        captchaKey: String
    ) async throws {
        var comps = URLComponents()
        comps.queryItems = [
            .init(name: "username", value: username),
            .init(name: "password", value: password),
            .init(name: "captchaCode", value: captchaCode),
            .init(name: "captchaKey", value: captchaKey)
        ]
        let body = Data((comps.percentEncodedQuery ?? "").utf8)
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/v1/auth/login",
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ],
            body: body
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.messageError(from: data, fallbackStatus: http.statusCode)
        }
        let env = try JSONDecoder().decode(SublinkEnvelope<SublinkLoginData>.self, from: data)
        guard env.isSuccess, let bearer = env.data?.bearer, !bearer.isEmpty else {
            throw NetworkError.message(env.errorText)
        }
        saveToken(bearer)
    }

    func ensureLogin(
        baseURL: String,
        username: String,
        password: String,
        captchaCode: String?,
        captchaKey: String?
    ) async throws {
        restoreToken()
        if token != nil { return }
        guard let captchaCode, let captchaKey, !captchaCode.isEmpty, !captchaKey.isEmpty else {
            throw NetworkError.message("请先完成验证码登录")
        }
        try await login(
            baseURL: baseURL,
            username: username,
            password: password,
            captchaCode: captchaCode,
            captchaKey: captchaKey
        )
    }

    // MARK: - Read

    func overview(baseURL: String) async throws -> SublinkDashboard {
        try await authorizedGet(baseURL: baseURL, path: "/api/v1/total/overview")
    }

    func nodes(baseURL: String) async throws -> [SublinkNode] {
        if let list: [SublinkNode] = try? await authorizedGet(baseURL: baseURL, path: "/api/v1/nodes/get") {
            return list
        }
        let box: SublinkListBox<SublinkNode> = try await authorizedGet(baseURL: baseURL, path: "/api/v1/nodes/get")
        return box.values
    }

    func subscriptions(baseURL: String) async throws -> [SublinkSub] {
        if let list: [SublinkSub] = try? await authorizedGet(baseURL: baseURL, path: "/api/v1/subcription/get") {
            return list
        }
        let box: SublinkListBox<SublinkSub> = try await authorizedGet(baseURL: baseURL, path: "/api/v1/subcription/get")
        return box.values
    }

    /// Group names as plain string array from `/api/v1/nodes/group/get`.
    func groups(baseURL: String) async throws -> [String] {
        if let list: [String] = try? await authorizedGet(baseURL: baseURL, path: "/api/v1/nodes/group/get") {
            return list.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return []
    }

    func probe(baseURL: String) async throws -> String {
        restoreToken()
        if token == nil { throw NetworkError.message("未登录 SublinkX") }
        let dash = try await overview(baseURL: baseURL)
        return "节点 \(dash.nodes) · 订阅 \(dash.subscriptions) · 访问 \(dash.accessCount)"
    }

    // MARK: - Nodes (write)

    func addNode(
        baseURL: String,
        name: String,
        link: String,
        group: String = ""
    ) async throws {
        try await authorizedForm(
            baseURL: baseURL,
            path: "/api/v1/nodes/add",
            method: "POST",
            fields: [
                "name": name,
                "link": link,
                "group": group
            ]
        )
    }

    func updateNode(
        baseURL: String,
        id: Int,
        name: String,
        link: String,
        group: String = ""
    ) async throws {
        try await authorizedForm(
            baseURL: baseURL,
            path: "/api/v1/nodes/update",
            method: "POST",
            fields: [
                "id": String(id),
                "name": name,
                "link": link,
                "group": group
            ]
        )
    }

    func deleteNode(baseURL: String, id: Int) async throws {
        try await authorizedAction(
            baseURL: baseURL,
            path: "/api/v1/nodes/delete",
            method: "DELETE",
            query: [.init(name: "id", value: String(id))]
        )
    }

    /// Bulk import: JSON `{"links":[...],"group":"..."}`.
    func bulkAddNodes(
        baseURL: String,
        links: [String],
        group: String = ""
    ) async throws -> SublinkBulkResult {
        struct Body: Encodable {
            let links: [String]
            let group: String
        }
        return try await authorizedJSON(
            baseURL: baseURL,
            path: "/api/v1/nodes/bulk",
            method: "POST",
            body: Body(links: links, group: group)
        )
    }

    func setNodeGroups(baseURL: String, nodeName: String, group: String) async throws {
        try await authorizedForm(
            baseURL: baseURL,
            path: "/api/v1/nodes/group/set",
            method: "POST",
            fields: [
                "name": nodeName,
                "group": group
            ]
        )
    }

    // MARK: - Subscriptions (write)

    func addSubscription(
        baseURL: String,
        name: String,
        nodeNames: [String],
        config: SublinkSubConfig = .default
    ) async throws {
        let nodesCSV = nodeNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        try await authorizedForm(
            baseURL: baseURL,
            path: "/api/v1/subcription/add",
            method: "POST",
            fields: [
                "name": name,
                "nodes": nodesCSV,
                "config": config.jsonString()
            ]
        )
    }

    func updateSubscription(
        baseURL: String,
        oldName: String,
        name: String,
        nodeNames: [String],
        config: SublinkSubConfig = .default
    ) async throws {
        let nodesCSV = nodeNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        try await authorizedForm(
            baseURL: baseURL,
            path: "/api/v1/subcription/update",
            method: "POST",
            fields: [
                "oldname": oldName,
                "name": name,
                "nodes": nodesCSV,
                "config": config.jsonString()
            ]
        )
    }

    func deleteSubscription(baseURL: String, id: Int) async throws {
        try await authorizedAction(
            baseURL: baseURL,
            path: "/api/v1/subcription/delete",
            method: "DELETE",
            query: [.init(name: "id", value: String(id))]
        )
    }

    // MARK: - HTTP helpers

    private func authorizedGet<T: Decodable>(
        baseURL: String,
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let data = try await authorizedRaw(
            baseURL: baseURL,
            path: path,
            method: "GET",
            query: query
        )
        let env = try JSONDecoder().decode(SublinkEnvelope<T>.self, from: data)
        guard env.isSuccess, let payload = env.data else {
            throw NetworkError.message(env.errorText)
        }
        return payload
    }

    private func authorizedForm(
        baseURL: String,
        path: String,
        method: String,
        fields: [String: String]
    ) async throws {
        var comps = URLComponents()
        comps.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = Data((comps.percentEncodedQuery ?? "").utf8)
        let data = try await authorizedRaw(
            baseURL: baseURL,
            path: path,
            method: method,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        try Self.requireSuccess(data)
    }

    private func authorizedJSON<T: Decodable>(
        baseURL: String,
        path: String,
        method: String,
        body: Encodable
    ) async throws -> T {
        let bodyData = try JSONEncoder().encode(AnyEncodable(body))
        let data = try await authorizedRaw(
            baseURL: baseURL,
            path: path,
            method: method,
            headers: ["Content-Type": "application/json"],
            body: bodyData
        )
        let env = try JSONDecoder().decode(SublinkEnvelope<T>.self, from: data)
        guard env.isSuccess, let payload = env.data else {
            throw NetworkError.message(env.errorText)
        }
        return payload
    }

    private func authorizedAction(
        baseURL: String,
        path: String,
        method: String,
        query: [URLQueryItem] = []
    ) async throws {
        let data = try await authorizedRaw(
            baseURL: baseURL,
            path: path,
            method: method,
            query: query
        )
        try Self.requireSuccess(data)
    }

    private func authorizedRaw(
        baseURL: String,
        path: String,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        query: [URLQueryItem] = []
    ) async throws -> Data {
        restoreToken()
        let merged = try authHeaders(extra: headers)
        let (data, http) = try await client.data(
            base: baseURL,
            path: path,
            method: method,
            headers: merged,
            body: body,
            query: query
        )
        if http.statusCode == 401 {
            logout()
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.messageError(from: data, fallbackStatus: http.statusCode)
        }
        return data
    }

    private static func requireSuccess(_ data: Data) throws {
        if let env = try? JSONDecoder().decode(SublinkStatusEnvelope.self, from: data) {
            if env.isSuccess { return }
            // Some handlers return 200 without code; only fail when code present and bad
            if env.code != nil {
                throw NetworkError.message(env.errorText)
            }
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let code = obj["code"] as? String, code != "00000", code != "0" {
                let msg = (obj["msg"] as? String) ?? (obj["message"] as? String) ?? "请求失败"
                throw NetworkError.message(msg)
            }
            if let code = obj["code"] as? Int, code != 0 {
                let msg = (obj["msg"] as? String) ?? (obj["message"] as? String) ?? "请求失败"
                throw NetworkError.message(msg)
            }
        }
    }

    private static func messageError(from data: Data, fallbackStatus: Int) -> Error {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = obj["msg"] as? String, !msg.isEmpty {
                return NetworkError.message(msg)
            }
            if let msg = obj["message"] as? String, !msg.isEmpty {
                return NetworkError.message(msg)
            }
        }
        return NetworkClient.httpError(status: fallbackStatus, body: data)
    }
}

// MARK: - Dashboard types (kept near service for overview decoding)

struct SublinkDashboard: Decodable {
    var subscriptions: Int64 = 0
    var nodes: Int64 = 0
    var groups: Int64 = 0
    var accessCount: Int64 = 0
    var protocols: [SublinkProtocolCount]?
    var recentAccess: [SublinkRecentAccess]?
    var generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case subscriptions, nodes, groups, protocols
        case accessCount, recentAccess, generatedAt
    }
}

struct SublinkProtocolCount: Decodable, Identifiable {
    var id: String { name }
    var name: String
    var count: Int
}

struct SublinkRecentAccess: Decodable, Identifiable {
    var id: String { "\(subscription)-\(date)-\(address)" }
    var subscription: String
    var date: String
    var address: String
    var count: Int
}

/// Type-erased Encodable for JSON helpers (mirrors NetworkClient pattern).
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encodeFunc = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
