import Foundation

/// Per-platform preferred play engine (native VLC vs in-app web).
enum LivePlayPrefs {
    enum Mode: String {
        case native
        case web
    }

    private static let prefix = "livePlayMode."

    static func preferred(for platform: LivePlatform) -> Mode {
        let key = prefix + platform.rawValue
        if let raw = UserDefaults.standard.string(forKey: key),
           let mode = Mode(rawValue: raw) {
            return mode
        }
        return .native
    }

    static func remember(_ mode: Mode, for platform: LivePlatform) {
        UserDefaults.standard.set(mode.rawValue, forKey: prefix + platform.rawValue)
    }
}

/// Short-lived room detail cache to cut open latency.
actor LiveDetailCache {
    static let shared = LiveDetailCache()

    private struct Entry {
        let detail: LiveRoomDetail
        let expires: Date
    }

    private var map: [String: Entry] = [:]
    private let ttl: TimeInterval = 45

    private func key(_ platform: LivePlatform, _ roomId: String) -> String {
        "\(platform.rawValue):\(roomId)"
    }

    func get(platform: LivePlatform, roomId: String) -> LiveRoomDetail? {
        let k = key(platform, roomId)
        guard let e = map[k], e.expires > Date() else {
            map[k] = nil
            return nil
        }
        return e.detail
    }

    func set(_ detail: LiveRoomDetail) {
        let k = key(detail.platform, detail.roomId)
        map[k] = Entry(detail: detail, expires: Date().addingTimeInterval(ttl))
    }
}
