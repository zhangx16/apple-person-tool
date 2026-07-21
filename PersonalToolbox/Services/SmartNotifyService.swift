import Foundation

/// Schedules / fires local notifications for check-in, subscriptions, certificates.
@MainActor
enum SmartNotifyService {
    static func evaluate(
        settings: AppSettings,
        checkin: CheckinSummary?,
        force: Bool = false
    ) {
        guard settings.notifySmartAlerts else { return }

        // Check-in failures
        if settings.notifyCheckinFailed, let projects = checkin?.projects {
            let failed = projects.filter { $0.statusKind == .failed }
            if !failed.isEmpty {
                let names = failed.prefix(3).map(\.displayTitle).joined(separator: "、")
                let more = failed.count > 3 ? " 等\(failed.count)项" : ""
                LocalNotifier.notify(
                    id: "smart.checkin.fail.\(dayKey())",
                    title: "签到异常",
                    body: "\(names)\(more) 失败，打开签到中心可补签",
                    category: LocalNotifier.smartCategory,
                    userInfo: ["route": "checkin"],
                    collapseByDay: true
                )
            }
        }

        // Subscriptions due within 7 days
        if settings.notifySubscriptionDue {
            let due = SubscriptionStore.shared.items.filter { $0.daysUntilDue >= 0 && $0.daysUntilDue <= 7 }
            if let first = due.sorted(by: { $0.daysUntilDue < $1.daysUntilDue }).first {
                LocalNotifier.notify(
                    id: "smart.sub.\(first.id).\(dayKey())",
                    title: "订阅即将到期",
                    body: "\(first.name) · \(first.daysUntilDue) 天后 · \(String(format: "%.2f", first.amount)) \(first.currency)",
                    category: LocalNotifier.smartCategory,
                    userInfo: ["route": "subscription"],
                    collapseByDay: true
                )
            }
        }

        // Certificates
        if settings.notifyCertExpiry {
            let expiring = CertExpiryStore.shared.items.filter { ($0.daysLeft ?? 999) <= 14 && ($0.daysLeft ?? 999) >= 0 }
            if let first = expiring.sorted(by: { ($0.daysLeft ?? 99) < ($1.daysLeft ?? 99) }).first,
               let days = first.daysLeft {
                LocalNotifier.notify(
                    id: "smart.cert.\(first.id).\(dayKey())",
                    title: "证书即将到期",
                    body: "\(first.host) · 剩余 \(days) 天",
                    category: LocalNotifier.smartCategory,
                    userInfo: ["route": "certs"],
                    collapseByDay: true
                )
            }
        }
    }

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}
