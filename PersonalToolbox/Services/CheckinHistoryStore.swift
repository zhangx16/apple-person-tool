import Foundation

/// Daily snapshots of check-in health for calendar heat map.
struct CheckinDaySnapshot: Identifiable, Codable, Hashable {
    var id: String { day } // yyyy-MM-dd
    var day: String
    var total: Int
    var healthy: Int
    var failed: Int
    var skipped: Int
    var updatedAt: Date

    var successRate: Double {
        guard total > 0 else { return 0 }
        return Double(healthy) / Double(total)
    }
}

@MainActor
final class CheckinHistoryStore: ObservableObject {
    static let shared = CheckinHistoryStore()
    private let fileName = "checkin_day_history.json"
    private let maxDays = 120

    @Published private(set) var days: [CheckinDaySnapshot] = []

    private init() {
        days = LocalJSONStore.load([CheckinDaySnapshot].self, from: fileName, fallback: [])
            .sorted { $0.day < $1.day }
    }

    private func persist() {
        LocalJSONStore.save(days, to: fileName)
    }

    static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func record(from summary: CheckinSummary?) {
        guard let c = summary?.counts else { return }
        let day = Self.dayString()
        let snap = CheckinDaySnapshot(
            day: day,
            total: c.totalValue,
            healthy: c.healthyValue,
            failed: c.failedValue,
            skipped: c.skippedValue,
            updatedAt: Date()
        )
        if let i = days.firstIndex(where: { $0.day == day }) {
            days[i] = snap
        } else {
            days.append(snap)
        }
        days.sort { $0.day < $1.day }
        if days.count > maxDays {
            days = Array(days.suffix(maxDays))
        }
        persist()
    }

    func snapshot(on day: String) -> CheckinDaySnapshot? {
        days.first { $0.day == day }
    }

    /// Last `count` days ending today (ascending).
    func recentDays(_ count: Int = 35) -> [CheckinDaySnapshot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [CheckinDaySnapshot] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = Self.dayString(d)
            if let snap = snapshot(on: key) {
                result.append(snap)
            } else {
                result.append(CheckinDaySnapshot(
                    day: key, total: 0, healthy: 0, failed: 0, skipped: 0, updatedAt: d
                ))
            }
        }
        return result
    }
}
