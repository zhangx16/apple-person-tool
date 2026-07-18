import Foundation

/// SublinkX (sublinkx-app) admin API client.
/// Base: https://sub.996616.xyz — JWT Bearer after form login with captcha.
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

    private func authHeaders() throws -> [String: String] {
        guard let token, !token.isEmpty else { throw NetworkError.unauthorized }
        return [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json"
        ]
    }

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
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["msg"] as? String {
                throw NetworkError.message(msg)
            }
            throw NetworkClient.httpError(status: http.statusCode, body: data)
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

    private func authorizedGet<T: Decodable>(
        baseURL: String,
        path: String
    ) async throws -> T {
        restoreToken()
        let headers = try authHeaders()
        let (data, http) = try await client.data(
            base: baseURL,
            path: path,
            headers: headers
        )
        if http.statusCode == 401 {
            logout()
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        let env = try JSONDecoder().decode(SublinkEnvelope<T>.self, from: data)
        guard env.isSuccess, let payload = env.data else {
            throw NetworkError.message(env.errorText)
        }
        return payload
    }

    func overview(baseURL: String) async throws -> SublinkDashboard {
        try await authorizedGet(baseURL: baseURL, path: "/api/v1/total/overview")
    }

    func nodes(baseURL: String) async throws -> [SublinkNode] {
        // API returns data as array of nodes directly
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

    func probe(baseURL: String) async throws -> String {
        restoreToken()
        if token == nil { throw NetworkError.message("未登录 SublinkX") }
        let dash = try await overview(baseURL: baseURL)
        return "节点 \(dash.nodes) · 订阅 \(dash.subscriptions) · 访问 \(dash.accessCount)"
    }
}

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
