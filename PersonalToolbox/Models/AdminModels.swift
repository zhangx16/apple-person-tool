import Foundation

/// Sub2API admin envelope: `{ code, message, data }` (code == 0 means success).
struct AdminEnvelope<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let reason: String?
    let data: T?
}

struct AdminDashboardStats: Decodable {
    var totalUsers: Int?
    var todayNewUsers: Int?
    var activeUsers: Int?
    var totalApiKeys: Int?
    var activeApiKeys: Int?
    var totalAccounts: Int?
    var normalAccounts: Int?
    var errorAccounts: Int?
    var totalRequests: Int?
    var totalCost: Double?
    var totalTokens: Int?
    var todayRequests: Int?
    var todayCost: Double?
    var todayTokens: Int?
    var rpm: Double?
    var tpm: Double?

    enum CodingKeys: String, CodingKey {
        case totalUsers = "total_users"
        case todayNewUsers = "today_new_users"
        case activeUsers = "active_users"
        case totalApiKeys = "total_api_keys"
        case activeApiKeys = "active_api_keys"
        case totalAccounts = "total_accounts"
        case normalAccounts = "normal_accounts"
        case errorAccounts = "error_accounts"
        case totalRequests = "total_requests"
        case totalCost = "total_cost"
        case totalTokens = "total_tokens"
        case todayRequests = "today_requests"
        case todayCost = "today_cost"
        case todayTokens = "today_tokens"
        case rpm, tpm
    }
}

struct AdminTrendPoint: Decodable, Identifiable {
    var id: String { date }
    var date: String
    var requests: Int?
    var totalTokens: Int?
    var cost: Double?

    enum CodingKeys: String, CodingKey {
        case date, requests, cost
        case totalTokens = "total_tokens"
    }
}

struct AdminDashboardTrend: Decodable {
    var startDate: String?
    var endDate: String?
    var granularity: String?
    var trend: [AdminTrendPoint]?

    enum CodingKeys: String, CodingKey {
        case granularity, trend
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct AdminModelStat: Decodable, Identifiable {
    var id: String { model }
    var model: String
    var requests: Int?
    var totalTokens: Int?
    var cost: Double?

    enum CodingKeys: String, CodingKey {
        case model, requests, cost
        case totalTokens = "total_tokens"
    }
}

struct AdminDashboardModels: Decodable {
    var models: [AdminModelStat]?
}

struct AdminAccount: Decodable, Identifiable {
    var id: Int
    var name: String?
    var platform: String?
    var type: String?
    var status: String?
    var schedulable: Bool?
    var errorMessage: String?
    var lastUsedAt: String?
    var currentConcurrency: Int?
    var concurrency: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, platform, type, status, schedulable, concurrency
        case errorMessage = "error_message"
        case lastUsedAt = "last_used_at"
        case currentConcurrency = "current_concurrency"
    }

    var hasError: Bool {
        status == "error" || !(errorMessage ?? "").isEmpty
    }
}

struct AdminPaginated<T: Decodable>: Decodable {
    var items: [T]?
    var total: Int?
    var page: Int?
    var pageSize: Int?

    enum CodingKeys: String, CodingKey {
        case items, total, page
        case pageSize = "page_size"
    }
}
