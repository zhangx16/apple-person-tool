import Foundation
import Combine

enum MonitorRange: String, CaseIterable, Identifiable {
    case h24 = "24h"
    case d7 = "7d"
    case d30 = "30d"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .h24: return "24H"
        case .d7: return "7D"
        case .d30: return "30D"
        }
    }
    var granularity: String { self == .h24 ? "hour" : "day" }
}

enum MonitorPane: String, CaseIterable, Identifiable {
    case overview
    case accounts
    case users
    case groups

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "概览"
        case .accounts: return "账号"
        case .users: return "用户"
        case .groups: return "分组"
        }
    }
}

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published var pane: MonitorPane = .overview
    @Published var range: MonitorRange = .d7
    @Published var stats: AdminDashboardStats?
    @Published var trend: [AdminTrendPoint] = []
    @Published var models: [AdminModelStat] = []
    @Published var accounts: [AdminAccount] = []
    @Published var users: [AdminUser] = []
    @Published var groups: [AdminGroup] = []
    @Published var accountSearch = ""
    @Published var userSearch = ""
    @Published var groupSearch = ""
    @Published var isLoading = false
    @Published var isMutating = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var lastUpdated: Date?
    @Published var accountTodayStats: [Int: AdminAccountTodayStats] = [:]

    private let service = Sub2AdminService.shared

    var filteredAccounts: [AdminAccount] {
        let q = accountSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return accounts }
        return accounts.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(q)
                || ($0.platform ?? "").localizedCaseInsensitiveContains(q)
                || ($0.status ?? "").localizedCaseInsensitiveContains(q)
                || String($0.id).contains(q)
        }
    }

    var filteredUsers: [AdminUser] {
        let q = userSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return users }
        return users.filter {
            ($0.email ?? "").localizedCaseInsensitiveContains(q)
                || ($0.username ?? "").localizedCaseInsensitiveContains(q)
                || String($0.id).contains(q)
        }
    }

    var filteredGroups: [AdminGroup] {
        let q = groupSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return groups }
        return groups.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(q)
                || ($0.platform ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    func load(settings: AppSettings) async {
        guard settings.isAdminConfigured else {
            errorMessage = "请在设置中填写 Sub2API Admin Token（x-api-key）"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let base = settings.sub2apiBaseURL
        let key = settings.sub2apiAdminAPIKey
        let dates = Self.dateRange(for: range)

        do {
            async let s = service.dashboardStats(baseURL: base, adminKey: key)
            async let t = service.dashboardTrend(
                baseURL: base,
                adminKey: key,
                startDate: dates.start,
                endDate: dates.end,
                granularity: range.granularity
            )
            async let m = service.dashboardModels(
                baseURL: base,
                adminKey: key,
                startDate: dates.start,
                endDate: dates.end
            )
            async let a = service.listAccounts(baseURL: base, adminKey: key, pageSize: 100)
            async let u = service.listUsers(baseURL: base, adminKey: key, pageSize: 100)
            async let g = service.listGroups(baseURL: base, adminKey: key, pageSize: 100)

            stats = try await s
            trend = try await t.trend ?? []
            models = (try await m.models ?? []).sorted { ($0.requests ?? 0) > ($1.requests ?? 0) }
            accounts = try await a.items ?? []
            users = try await u.items ?? []
            groups = try await g.items ?? []
            lastUpdated = Date()
        } catch {
            errorMessage = Self.errText(error)
        }
    }

    func refreshAccounts(settings: AppSettings) async {
        guard settings.isAdminConfigured else { return }
        do {
            let page = try await service.listAccounts(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                pageSize: 100,
                search: accountSearch
            )
            accounts = page.items ?? []
        } catch {
            errorMessage = Self.errText(error)
        }
    }

    func refreshUsers(settings: AppSettings) async {
        guard settings.isAdminConfigured else { return }
        do {
            let page = try await service.listUsers(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                pageSize: 100,
                search: userSearch
            )
            users = page.items ?? []
        } catch {
            errorMessage = Self.errText(error)
        }
    }

    // MARK: - Account actions

    func toggleSchedulable(settings: AppSettings, account: AdminAccount) async {
        let next = !(account.schedulable ?? true)
        await mutate(settings: settings) {
            let updated = try await service.setAccountSchedulable(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                id: account.id,
                schedulable: next
            )
            if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[idx] = updated
            }
            statusMessage = next ? "已开启调度：\(account.displayName)" : "已暂停调度：\(account.displayName)"
        }
    }

    func testAccount(settings: AppSettings, account: AdminAccount) async {
        await mutate(settings: settings) {
            try await service.testAccount(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                id: account.id
            )
            statusMessage = "测试已触发：\(account.displayName)"
            await refreshAccounts(settings: settings)
        }
    }

    func refreshAccount(settings: AppSettings, account: AdminAccount) async {
        await mutate(settings: settings) {
            try await service.refreshAccount(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                id: account.id
            )
            statusMessage = "刷新已触发：\(account.displayName)"
            await refreshAccounts(settings: settings)
        }
    }

    func loadTodayStats(settings: AppSettings, accountId: Int) async {
        guard settings.isAdminConfigured else { return }
        do {
            let stats = try await service.accountTodayStats(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                id: accountId
            )
            accountTodayStats[accountId] = stats
        } catch {
            errorMessage = Self.errText(error)
        }
    }

    // MARK: - User actions

    func setUserStatus(settings: AppSettings, user: AdminUser, active: Bool) async {
        let status = active ? "active" : "disabled"
        await mutate(settings: settings) {
            let updated = try await service.updateUserStatus(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                id: user.id,
                status: status
            )
            if let idx = users.firstIndex(where: { $0.id == user.id }) {
                users[idx] = updated
            }
            statusMessage = active ? "已启用 \(user.displayName)" : "已禁用 \(user.displayName)"
        }
    }

    func adjustBalance(
        settings: AppSettings,
        user: AdminUser,
        amount: Double,
        operation: AdminBalanceOperation,
        notes: String
    ) async -> Bool {
        await mutate(settings: settings) {
            let updated = try await service.updateUserBalance(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                id: user.id,
                balance: amount,
                operation: operation,
                notes: notes.isEmpty ? nil : notes
            )
            if let idx = users.firstIndex(where: { $0.id == user.id }) {
                users[idx] = updated
            }
            statusMessage = "余额已更新：\(user.displayName)"
        }
    }

    func loadUserApiKeys(settings: AppSettings, userId: Int) async -> [AdminApiKey] {
        guard settings.isAdminConfigured else { return [] }
        do {
            let page = try await service.listUserApiKeys(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey,
                userId: userId
            )
            return page.items ?? []
        } catch {
            errorMessage = Self.errText(error)
            return []
        }
    }

    // MARK: - Internals

    @discardableResult
    private func mutate(
        settings: AppSettings,
        _ work: () async throws -> Void
    ) async -> Bool {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            try await work()
            Haptics.success()
            return true
        } catch {
            errorMessage = Self.errText(error)
            Haptics.error()
            return false
        }
    }

    static func dateRange(for range: MonitorRange) -> (start: String, end: String) {
        let end = Date()
        var start = Date()
        let cal = Calendar.current
        switch range {
        case .h24:
            start = cal.date(byAdding: .hour, value: -23, to: end) ?? end
        case .d7:
            start = cal.date(byAdding: .day, value: -6, to: end) ?? end
        case .d30:
            start = cal.date(byAdding: .day, value: -29, to: end) ?? end
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return (f.string(from: start), f.string(from: end))
    }

    private static func errText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
