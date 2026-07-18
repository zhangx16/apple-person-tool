import Foundation

/// Sub2API admin envelope: `{ code, message, data }` (code == 0 means success).
struct AdminEnvelope<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let reason: String?
    let data: T?
}

/// Status-only envelope (write endpoints that may omit data).
struct AdminStatusEnvelope: Decodable {
    let code: Int?
    let message: String?
    let reason: String?

    var isSuccess: Bool {
        (code ?? 0) == 0
    }

    var errorText: String {
        reason ?? message ?? "管理接口错误"
    }
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

struct AdminAccount: Decodable, Identifiable, Hashable {
    var id: Int
    var name: String?
    var platform: String?
    var type: String?
    var status: String?
    var schedulable: Bool?
    var errorMessage: String?
    var lastUsedAt: String?
    var updatedAt: String?
    var currentConcurrency: Int?
    var concurrency: Int?
    var priority: Int?
    var rateMultiplier: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, platform, type, status, schedulable, concurrency, priority
        case errorMessage = "error_message"
        case lastUsedAt = "last_used_at"
        case updatedAt = "updated_at"
        case currentConcurrency = "current_concurrency"
        case rateMultiplier = "rate_multiplier"
    }

    var hasError: Bool {
        status == "error" || !(errorMessage ?? "").isEmpty
    }

    var displayName: String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "账号 #\(id)" : n
    }
}

struct AdminAccountTodayStats: Decodable {
    var requests: Int?
    var tokens: Int?
    var cost: Double?
    var standardCost: Double?
    var userCost: Double?

    enum CodingKeys: String, CodingKey {
        case requests, tokens, cost
        case standardCost = "standard_cost"
        case userCost = "user_cost"
    }
}

struct AdminUser: Decodable, Identifiable, Hashable {
    var id: Int
    var email: String?
    var username: String?
    var balance: Double?
    var concurrency: Int?
    var currentConcurrency: Int?
    var status: String?
    var role: String?
    var notes: String?
    var lastUsedAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, username, balance, concurrency, status, role, notes
        case currentConcurrency = "current_concurrency"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
    }

    var displayName: String {
        if let u = username, !u.isEmpty { return u }
        if let e = email, !e.isEmpty { return e }
        return "用户 #\(id)"
    }

    var isActive: Bool {
        (status ?? "active") == "active"
    }
}

struct AdminApiKey: Decodable, Identifiable, Hashable {
    var id: Int
    var userId: Int?
    var key: String?
    var name: String?
    var status: String?
    var quota: Double?
    var quotaUsed: Double?
    var lastUsedAt: String?
    var expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, key, name, status, quota
        case userId = "user_id"
        case quotaUsed = "quota_used"
        case lastUsedAt = "last_used_at"
        case expiresAt = "expires_at"
    }

    var displayName: String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "Key #\(id)" : n
    }

    var maskedKey: String {
        guard let key, key.count > 8 else { return key ?? "—" }
        return String(key.prefix(4)) + "…" + String(key.suffix(4))
    }
}

struct AdminGroup: Decodable, Identifiable, Hashable {
    var id: Int
    var name: String?
    var description: String?
    var platform: String?
    var rateMultiplier: Double?
    var status: String?
    var accountCount: Int?
    var dailyLimitUsd: Double?
    var weeklyLimitUsd: Double?
    var monthlyLimitUsd: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, description, platform, status
        case rateMultiplier = "rate_multiplier"
        case accountCount = "account_count"
        case dailyLimitUsd = "daily_limit_usd"
        case weeklyLimitUsd = "weekly_limit_usd"
        case monthlyLimitUsd = "monthly_limit_usd"
    }

    var displayName: String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "分组 #\(id)" : n
    }
}

enum AdminBalanceOperation: String, CaseIterable, Identifiable {
    case set
    case add
    case subtract

    var id: String { rawValue }

    var title: String {
        switch self {
        case .set: return "设为"
        case .add: return "增加"
        case .subtract: return "扣减"
        }
    }
}

struct AdminPaginated<T: Decodable>: Decodable {
    var items: [T]?
    var total: Int?
    var page: Int?
    var pageSize: Int?
    var pages: Int?

    enum CodingKeys: String, CodingKey {
        case items, total, page, pages
        case pageSize = "page_size"
    }
}
