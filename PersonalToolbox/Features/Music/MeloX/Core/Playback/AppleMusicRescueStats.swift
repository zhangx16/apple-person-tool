import Foundation

/// Counts how often Apple Music "rescued" a Netease trial / no-source play.
@MainActor
@Observable
final class AppleMusicRescueStats {
    static let shared = AppleMusicRescueStats()

    private let defaults = UserDefaults.standard
    private let eventsKey = "melox.appleMusicRescueEvents.v1"
    /// (timeIntervalSince1970, neteaseSongID)
    private(set) var events: [(Date, Int)] = []

    private init() {
        load()
    }

    func record(neteaseSongID: Int, reason: String) {
        let now = Date()
        events.append((now, neteaseSongID))
        // Keep ~90 days.
        let cutoff = now.addingTimeInterval(-90 * 24 * 3600)
        events.removeAll { $0.0 < cutoff }
        persist()
    }

    var weekCount: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return events.filter { $0.0 >= cutoff }.count
    }

    var monthCount: Int {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        return events.filter { $0.0 >= cutoff }.count
    }

    var totalCount: Int { events.count }

    func clear() {
        events = []
        defaults.removeObject(forKey: eventsKey)
    }

    private func load() {
        guard let raw = defaults.array(forKey: eventsKey) as? [[String: Any]] else {
            events = []
            return
        }
        events = raw.compactMap { dict in
            guard let t = dict["t"] as? Double,
                  let id = dict["id"] as? Int else { return nil }
            return (Date(timeIntervalSince1970: t), id)
        }
    }

    private func persist() {
        let payload: [[String: Any]] = events.map {
            ["t": $0.0.timeIntervalSince1970, "id": $0.1]
        }
        defaults.set(payload, forKey: eventsKey)
    }
}
