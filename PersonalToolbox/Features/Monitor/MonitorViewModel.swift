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

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published var range: MonitorRange = .d7
    @Published var stats: AdminDashboardStats?
    @Published var trend: [AdminTrendPoint] = []
    @Published var models: [AdminModelStat] = []
    @Published var accounts: [AdminAccount] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let service = Sub2AdminService.shared

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
            async let a = service.listAccounts(baseURL: base, adminKey: key)

            stats = try await s
            trend = try await t.trend ?? []
            models = (try await m.models ?? []).sorted { ($0.requests ?? 0) > ($1.requests ?? 0) }
            accounts = try await a.items ?? []
            lastUpdated = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func dateRange(for range: MonitorRange) -> (start: String, end: String) {
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
}
