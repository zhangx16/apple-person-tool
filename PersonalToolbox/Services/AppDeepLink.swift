import Foundation
import Combine

/// App-wide deep link / pending action bus (notifications, clipboard smart bar).
@MainActor
final class AppDeepLinkStore: ObservableObject {
    static let shared = AppDeepLinkStore()

    /// Switch tab request (overview / live / music / services / settings).
    @Published var requestedTab: AppTab?
    /// Live room to open once Live tab is visible.
    @Published var pendingLive: PendingLiveRoom?
    /// Prefill download URL and auto-parse.
    @Published var pendingDownloadURL: String?
    /// Prefill IP check.
    @Published var pendingIP: String?
    /// Prefill express tracking.
    @Published var pendingExpress: String?
    /// Music: raw netease URL or search keyword for search tab hint.
    @Published var pendingMusicURL: String?
    /// Present services module sheet.
    @Published var presentSheet: DeepLinkSheet?

    struct PendingLiveRoom: Equatable {
        var platform: LivePlatform
        var roomId: String
        var userName: String
    }

    enum DeepLinkSheet: Identifiable, Equatable {
        case ipCheck(String?)
        case download(String)
        case express(String)
        case watchLater
        case proxyPack
        case controlCenter
        case subscriptions

        var id: String {
            switch self {
            case .ipCheck(let ip): return "ip-\(ip ?? "self")"
            case .download(let u): return "dl-\(u.prefix(40))"
            case .express(let t): return "ex-\(t)"
            case .watchLater: return "wl"
            case .proxyPack: return "proxy"
            case .controlCenter: return "cc"
            case .subscriptions: return "sub"
            }
        }
    }

    private init() {}

    func openLive(platform: LivePlatform, roomId: String, userName: String = "") {
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return }
        pendingLive = PendingLiveRoom(platform: platform, roomId: rid, userName: userName)
        requestedTab = .live
    }

    func openDownload(url: String) {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        pendingDownloadURL = u
        presentSheet = .download(u)
    }

    func openIP(_ ip: String?) {
        presentSheet = .ipCheck(ip)
    }

    func openExpress(_ tracking: String) {
        presentSheet = .express(tracking)
    }

    func openMusic(url: String) {
        pendingMusicURL = url
        requestedTab = .music
    }

    func consumeLive() -> PendingLiveRoom? {
        let v = pendingLive
        pendingLive = nil
        return v
    }

    func consumeDownloadURL() -> String? {
        let v = pendingDownloadURL
        pendingDownloadURL = nil
        return v
    }

    func consumeMusicURL() -> String? {
        let v = pendingMusicURL
        pendingMusicURL = nil
        return v
    }

    /// Handle notification / legacy route payloads.
    func handleUserInfo(_ info: [AnyHashable: Any]) {
        let route = (info["route"] as? String) ?? ""
        switch route {
        case "live":
            let platformRaw = (info["platform"] as? String) ?? ""
            let roomId = (info["roomId"] as? String) ?? ""
            let name = (info["userName"] as? String) ?? ""
            if let p = LivePlatform(rawValue: platformRaw), !roomId.isEmpty {
                openLive(platform: p, roomId: roomId, userName: name)
            } else {
                requestedTab = .live
            }
        case "download":
            if let url = info["url"] as? String, !url.isEmpty {
                openDownload(url: url)
            } else {
                requestedTab = .services
                presentSheet = .download("")
            }
        case "ip":
            openIP(info["ip"] as? String)
        case "express":
            if let t = info["tracking"] as? String { openExpress(t) }
        case "music":
            if let u = info["url"] as? String { openMusic(url: u) }
            else { requestedTab = .music }
        case "subscription":
            presentSheet = .subscriptions
        case "certs", "checkin", "health", "notes", "ssh", "reminder":
            // Overview handles via its own path when on overview tab.
            requestedTab = .overview
            NotificationCenter.default.post(
                name: ForegroundNotificationDelegate.routeNotification,
                object: nil,
                userInfo: info
            )
        case "proxy":
            presentSheet = .proxyPack
        case "settings":
            requestedTab = .settings
        default:
            if let platformRaw = info["platform"] as? String,
               let roomId = info["roomId"] as? String,
               let p = LivePlatform(rawValue: platformRaw) {
                openLive(platform: p, roomId: roomId, userName: (info["userName"] as? String) ?? "")
            }
        }
    }
}

// MARK: - Quiet hours / notify gate

enum NotifyGate {
    /// Returns false if we should suppress non-critical local notifications.
    static func allowsSmartNotify(settings: AppSettings) -> Bool {
        guard settings.notifySmartAlerts else { return false }
        guard settings.notifyQuietHoursEnabled else { return true }
        let hour = Calendar.current.component(.hour, from: Date())
        let start = settings.notifyQuietStartHour
        let end = settings.notifyQuietEndHour
        // e.g. 23 → 8 spans midnight
        if start == end { return true }
        if start < end {
            // quiet during [start, end)
            return !(hour >= start && hour < end)
        } else {
            // quiet during [start, 24) U [0, end)
            return !(hour >= start || hour < end)
        }
    }
}
