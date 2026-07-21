import Foundation
import UserNotifications
import UIKit

/// Thin wrapper around `UNUserNotificationCenter` for app-wide local notifications.
enum LocalNotifier {
    static let downloadCategory = "download.completed"
    static let smartCategory = "smart.alert"
    private static let downloadPrefix = "download."
    /// In-memory de-dupe for same-id within a process.
    private static var recentIds = Set<String>()

    // MARK: - Permission

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Ensure permission when a feature is turned on. Returns whether notifications may be delivered.
    @discardableResult
    static func ensureAuthorized() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Deliver

    /// Fire a local notification ASAP (works in background; foreground needs delegate).
    static func notify(
        id: String,
        title: String,
        body: String,
        category: String? = nil,
        userInfo: [AnyHashable: Any] = [:],
        sound: Bool = true,
        collapseByDay: Bool = false
    ) {
        if collapseByDay, recentIds.contains(id) { return }
        recentIds.insert(id)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        if sound {
            content.sound = .default
        }
        if let category {
            content.categoryIdentifier = category
        }

        // Slight delay so delivery is reliable when leaving the app mid-callback.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.4, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    static func notifyDownloadCompleted(taskId: String, title: String, source: String) {
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = safeTitle.isEmpty ? "下载任务" : safeTitle
        notify(
            id: "\(downloadPrefix)ok.\(taskId)",
            title: "下载完成",
            body: "\(source)：\(display)",
            category: downloadCategory,
            userInfo: ["route": "download", "taskId": taskId]
        )
    }

    static func notifyDownloadFailed(taskId: String, title: String, source: String, reason: String?) {
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = safeTitle.isEmpty ? "下载任务" : safeTitle
        let detail = (reason?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let body = detail.map { "\(source)：\(display)\n\($0)" } ?? "\(source)：\(display)"
        notify(
            id: "\(downloadPrefix)fail.\(taskId)",
            title: "下载失败",
            body: body,
            category: downloadCategory,
            userInfo: ["route": "download", "taskId": taskId]
        )
    }

    // MARK: - Foreground presentation

    /// Call once from app launch so banners appear while the app is open.
    static func installForegroundDelegate() {
        let center = UNUserNotificationCenter.current()
        if !(center.delegate is ForegroundNotificationDelegate) {
            center.delegate = ForegroundNotificationDelegate.shared
        }
        // Actions: open related module
        let open = UNNotificationAction(identifier: "OPEN", title: "打开", options: [.foreground])
        let downloadCat = UNNotificationCategory(
            identifier: downloadCategory,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        let smartCat = UNNotificationCategory(
            identifier: smartCategory,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([downloadCat, smartCat])
    }
}

/// Shows banners/list/sound when a local notification arrives in the foreground.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationDelegate()

    /// Deep-link route posted to the app (checkin / download / subscription / certs).
    static let routeNotification = Notification.Name("LocalNotifier.route")

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let route = info["route"] as? String, !route.isEmpty {
            NotificationCenter.default.post(
                name: Self.routeNotification,
                object: nil,
                userInfo: ["route": route]
            )
        }
        completionHandler()
    }
}
