import Foundation

/// Shared suite for Widget + main app snapshots.
enum AppGroupShared {
    static let suiteName = "group.app.parsnip6345.lake8262"

    /// Falls back to standard defaults when App Group is not enabled on the provisioning profile.
    static var defaults: UserDefaults {
        if let suite = UserDefaults(suiteName: suiteName),
           // suiteName returns non-nil even without entitlement on some OS versions; still write.
           true {
            return suite
        }
        return .standard
    }

    enum Key {
        static let checkinHealthy = "widget.checkin.healthy"
        static let checkinTotal = "widget.checkin.total"
        static let checkinFailed = "widget.checkin.failed"
        static let subscriptionDueCount = "widget.sub.due"
        static let subscriptionNextName = "widget.sub.nextName"
        static let subscriptionNextDays = "widget.sub.nextDays"
        static let updatedAt = "widget.updatedAt"
        static let headline = "widget.headline"
    }

    static func publish(
        checkinHealthy: Int,
        checkinTotal: Int,
        checkinFailed: Int,
        dueSubs: Int,
        nextSubName: String?,
        nextSubDays: Int?
    ) {
        let d = defaults
        d.set(checkinHealthy, forKey: Key.checkinHealthy)
        d.set(checkinTotal, forKey: Key.checkinTotal)
        d.set(checkinFailed, forKey: Key.checkinFailed)
        d.set(dueSubs, forKey: Key.subscriptionDueCount)
        d.set(nextSubName ?? "", forKey: Key.subscriptionNextName)
        d.set(nextSubDays ?? -1, forKey: Key.subscriptionNextDays)
        d.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        let head: String
        if checkinTotal > 0 {
            head = checkinFailed > 0
                ? "签到 \(checkinHealthy)/\(checkinTotal) · \(checkinFailed) 失败"
                : "签到 \(checkinHealthy)/\(checkinTotal) 正常"
        } else if dueSubs > 0 {
            head = "\(dueSubs) 笔订阅即将到期"
        } else {
            head = "XIN's Tool"
        }
        d.set(head, forKey: Key.headline)
    }
}
