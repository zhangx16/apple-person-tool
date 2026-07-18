import Foundation

/// Sub2API admin console client (aligned with [sub2api-mobile](https://github.com/ckken/sub2api-mobile)).
/// Auth: `x-api-key: <Admin API Key>` on `/api/v1/admin/*`.
actor Sub2AdminService {
    static let shared = Sub2AdminService()
    private let client = NetworkClient.shared

    private func headers(adminKey: String, idempotencyKey: String? = nil) -> [String: String] {
        var h: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "x-api-key": adminKey
        ]
        if let idempotencyKey, !idempotencyKey.isEmpty {
            h["Idempotency-Key"] = idempotencyKey
        }
        return h
    }

    // MARK: - Dashboard

    func dashboardStats(baseURL: String, adminKey: String) async throws -> AdminDashboardStats {
        try await get(baseURL: baseURL, path: "/api/v1/admin/dashboard/stats", adminKey: adminKey)
    }

    func dashboardTrend(
        baseURL: String,
        adminKey: String,
        startDate: String,
        endDate: String,
        granularity: String = "day"
    ) async throws -> AdminDashboardTrend {
        try await get(
            baseURL: baseURL,
            path: "/api/v1/admin/dashboard/trend",
            adminKey: adminKey,
            query: [
                .init(name: "start_date", value: startDate),
                .init(name: "end_date", value: endDate),
                .init(name: "granularity", value: granularity)
            ]
        )
    }

    func dashboardModels(
        baseURL: String,
        adminKey: String,
        startDate: String,
        endDate: String
    ) async throws -> AdminDashboardModels {
        try await get(
            baseURL: baseURL,
            path: "/api/v1/admin/dashboard/models",
            adminKey: adminKey,
            query: [
                .init(name: "start_date", value: startDate),
                .init(name: "end_date", value: endDate)
            ]
        )
    }

    // MARK: - Accounts

    func listAccounts(
        baseURL: String,
        adminKey: String,
        page: Int = 1,
        pageSize: Int = 50,
        search: String = ""
    ) async throws -> AdminPaginated<AdminAccount> {
        var q: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "page_size", value: String(pageSize))
        ]
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            q.append(.init(name: "search", value: search.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return try await get(
            baseURL: baseURL,
            path: "/api/v1/admin/accounts",
            adminKey: adminKey,
            query: q
        )
    }

    func getAccount(baseURL: String, adminKey: String, id: Int) async throws -> AdminAccount {
        try await get(baseURL: baseURL, path: "/api/v1/admin/accounts/\(id)", adminKey: adminKey)
    }

    func accountTodayStats(baseURL: String, adminKey: String, id: Int) async throws -> AdminAccountTodayStats {
        try await get(
            baseURL: baseURL,
            path: "/api/v1/admin/accounts/\(id)/today-stats",
            adminKey: adminKey
        )
    }

    func testAccount(baseURL: String, adminKey: String, id: Int) async throws {
        try await postEmpty(
            baseURL: baseURL,
            path: "/api/v1/admin/accounts/\(id)/test",
            adminKey: adminKey
        )
    }

    func refreshAccount(baseURL: String, adminKey: String, id: Int) async throws {
        try await postEmpty(
            baseURL: baseURL,
            path: "/api/v1/admin/accounts/\(id)/refresh",
            adminKey: adminKey
        )
    }

    func setAccountSchedulable(
        baseURL: String,
        adminKey: String,
        id: Int,
        schedulable: Bool
    ) async throws -> AdminAccount {
        try await send(
            baseURL: baseURL,
            path: "/api/v1/admin/accounts/\(id)/schedulable",
            method: "POST",
            adminKey: adminKey,
            body: ["schedulable": schedulable]
        )
    }

    // MARK: - Users

    func listUsers(
        baseURL: String,
        adminKey: String,
        page: Int = 1,
        pageSize: Int = 50,
        search: String = ""
    ) async throws -> AdminPaginated<AdminUser> {
        var q: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "page_size", value: String(pageSize))
        ]
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            q.append(.init(name: "search", value: search.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return try await get(
            baseURL: baseURL,
            path: "/api/v1/admin/users",
            adminKey: adminKey,
            query: q
        )
    }

    func getUser(baseURL: String, adminKey: String, id: Int) async throws -> AdminUser {
        try await get(baseURL: baseURL, path: "/api/v1/admin/users/\(id)", adminKey: adminKey)
    }

    func updateUserStatus(
        baseURL: String,
        adminKey: String,
        id: Int,
        status: String
    ) async throws -> AdminUser {
        try await send(
            baseURL: baseURL,
            path: "/api/v1/admin/users/\(id)",
            method: "PUT",
            adminKey: adminKey,
            body: ["status": status]
        )
    }

    func updateUserBalance(
        baseURL: String,
        adminKey: String,
        id: Int,
        balance: Double,
        operation: AdminBalanceOperation,
        notes: String? = nil
    ) async throws -> AdminUser {
        var body: [String: Any] = [
            "balance": balance,
            "operation": operation.rawValue
        ]
        if let notes, !notes.isEmpty {
            body["notes"] = notes
        }
        return try await send(
            baseURL: baseURL,
            path: "/api/v1/admin/users/\(id)/balance",
            method: "POST",
            adminKey: adminKey,
            body: body,
            idempotencyKey: "user-balance-\(id)-\(Int(Date().timeIntervalSince1970 * 1000))"
        )
    }

    func listUserApiKeys(
        baseURL: String,
        adminKey: String,
        userId: Int
    ) async throws -> AdminPaginated<AdminApiKey> {
        try await get(
            baseURL: baseURL,
            path: "/api/v1/admin/users/\(userId)/api-keys",
            adminKey: adminKey,
            query: [
                .init(name: "page", value: "1"),
                .init(name: "page_size", value: "100")
            ]
        )
    }

    // MARK: - Groups

    func listGroups(
        baseURL: String,
        adminKey: String,
        page: Int = 1,
        pageSize: Int = 50,
        search: String = ""
    ) async throws -> AdminPaginated<AdminGroup> {
        var q: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "page_size", value: String(pageSize))
        ]
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            q.append(.init(name: "search", value: search.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return try await get(
            baseURL: baseURL,
            path: "/api/v1/admin/groups",
            adminKey: adminKey,
            query: q
        )
    }

    func probe(baseURL: String, adminKey: String) async throws -> String {
        let stats = try await dashboardStats(baseURL: baseURL, adminKey: adminKey)
        let req = stats.todayRequests.map(String.init) ?? "?"
        let cost = stats.todayCost.map { String(format: "%.2f", $0) } ?? "?"
        let err = stats.errorAccounts.map(String.init) ?? "?"
        return "今日请求 \(req) · $\(cost) · 异常账号 \(err)"
    }

    // MARK: - HTTP

    private func get<T: Decodable>(
        baseURL: String,
        path: String,
        adminKey: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        try await send(
            baseURL: baseURL,
            path: path,
            method: "GET",
            adminKey: adminKey,
            query: query,
            body: nil as [String: Any]?
        )
    }

    private func postEmpty(
        baseURL: String,
        path: String,
        adminKey: String
    ) async throws {
        let (data, http) = try await client.data(
            base: baseURL,
            path: path,
            method: "POST",
            headers: headers(adminKey: adminKey),
            body: Data("{}".utf8)
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.messageError(from: data, status: http.statusCode)
        }
        if let env = try? JSONDecoder().decode(AdminStatusEnvelope.self, from: data), !env.isSuccess {
            throw NetworkError.message(env.errorText)
        }
    }

    private func send<T: Decodable>(
        baseURL: String,
        path: String,
        method: String,
        adminKey: String,
        query: [URLQueryItem] = [],
        body: [String: Any]?,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let bodyData: Data?
        if let body {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } else {
            bodyData = nil
        }
        let (data, http) = try await client.data(
            base: baseURL,
            path: path,
            method: method,
            headers: headers(adminKey: adminKey, idempotencyKey: idempotencyKey),
            body: bodyData,
            query: query
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.messageError(from: data, status: http.statusCode)
        }
        let env = try JSONDecoder().decode(AdminEnvelope<T>.self, from: data)
        if let code = env.code, code != 0 {
            throw NetworkError.message(env.reason ?? env.message ?? "管理接口错误 (\(code))")
        }
        guard let payload = env.data else {
            throw NetworkError.message(env.message ?? "管理接口无数据")
        }
        return payload
    }

    private static func messageError(from data: Data, status: Int) -> Error {
        if let env = try? JSONDecoder().decode(AdminStatusEnvelope.self, from: data) {
            let text = env.errorText
            if !text.isEmpty { return NetworkError.message(text) }
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = obj["message"] as? String, !msg.isEmpty {
                return NetworkError.message(msg)
            }
            if let msg = obj["reason"] as? String, !msg.isEmpty {
                return NetworkError.message(msg)
            }
        }
        return NetworkClient.httpError(status: status, body: data)
    }
}
