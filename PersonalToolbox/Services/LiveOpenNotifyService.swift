import Foundation

/// Poll follow list and fire local notifications when a streamer goes live.
@MainActor
enum LiveOpenNotifyService {
    private static let lastLiveKey = "liveOpenNotify.lastLiveIds.v1"
    private static var lastCheckAt: Date?

    /// Call on overview refresh / app become active (throttled).
    static func evaluate(settings: AppSettings, force: Bool = false) {
        guard settings.notifyLiveOpen else { return }
        guard NotifyGate.allowsSmartNotify(settings: settings) else { return }
        if !force, let last = lastCheckAt, Date().timeIntervalSince(last) < 90 {
            return
        }
        lastCheckAt = Date()

        LiveFollowStore.shared.refreshMetadata(for: nil, forceStatus: true)
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                self.diffAndNotify(settings: settings)
            }
        }
    }

    private static func diffAndNotify(settings: AppSettings) {
        guard settings.notifyLiveOpen, NotifyGate.allowsSmartNotify(settings: settings) else { return }

        let liveItems = LiveFollowStore.shared.items.filter { $0.isLive == true }
        let liveNow = Set(liveItems.map(\.id))
        let stored = UserDefaults.standard.stringArray(forKey: lastLiveKey)
        // First run: seed baseline without notifying (avoid flood).
        guard let stored else {
            UserDefaults.standard.set(Array(liveNow), forKey: lastLiveKey)
            return
        }
        let previous = Set(stored)
        let newly = liveNow.subtracting(previous)
        UserDefaults.standard.set(Array(liveNow), forKey: lastLiveKey)

        guard !newly.isEmpty else { return }
        let streamers = liveItems.filter { newly.contains($0.id) }
        guard !streamers.isEmpty else { return }

        if streamers.count == 1, let item = streamers.first {
            LocalNotifier.notify(
                id: "live.open.\(item.id).\(dayKey())",
                title: "关注的主播开播了",
                body: "\(item.displayName) · \(item.platform.title)",
                category: LocalNotifier.smartCategory,
                userInfo: [
                    "route": "live",
                    "platform": item.platform.rawValue,
                    "roomId": item.roomId,
                    "userName": item.displayName
                ],
                collapseByDay: true
            )
        } else {
            // Aggregate multi-open into one notification; primary room = first.
            let names = streamers.prefix(3).map(\.displayName).joined(separator: "、")
            let more = streamers.count > 3 ? " 等\(streamers.count)人" : ""
            let primary = streamers[0]
            LocalNotifier.notify(
                id: "live.open.batch.\(dayKey())",
                title: "\(streamers.count) 位关注主播开播了",
                body: "\(names)\(more)",
                category: LocalNotifier.smartCategory,
                userInfo: [
                    "route": "live",
                    "platform": primary.platform.rawValue,
                    "roomId": primary.roomId,
                    "userName": primary.displayName
                ],
                collapseByDay: true
            )
        }
    }

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHH"
        return f.string(from: Date())
    }
}
