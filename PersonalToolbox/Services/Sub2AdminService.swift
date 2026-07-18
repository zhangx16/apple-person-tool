import Foundation

/// Sub2API admin console client (mirrors sub2api-mobile `adminFetch` + dashboard APIs).
/// Auth: `x-api-key: <Admin API Key>` on `/api/v1/admin/*`.
actor Sub2AdminService {
    static let shared = Sub2AdminService()
    private let client = NetworkClient.shared

    private func headers(adminKey: String) -> [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "x-api-key": adminKey
        ]
    }

    private func get<T: Decodable>(
        baseURL: String,
        path: String,
        adminKey: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let (data, http) = try await client.data(
            base: baseURL,
            path: path,
            headers: headers(adminKey: adminKey),
            query: query
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
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
        if !search.isEmpty {
            q.append(.init(name: "search", value: search))
        }
        return try await get(
            baseURL: baseURL,
            path: "/api/v1/admin/accounts",
            adminKey: adminKey,
            query: q
        )
    }

    func probe(baseURL: String, adminKey: String) async throws -> String {
        let stats = try await dashboardStats(baseURL: baseURL, adminKey: adminKey)
        let req = stats.todayRequests.map(String.init) ?? "?"
        let cost = stats.todayCost.map { String(format: "%.2f" , $0) } ?? "?"
        return "今日请求 \(req) · 费用 $\(cost)"
    }
}
