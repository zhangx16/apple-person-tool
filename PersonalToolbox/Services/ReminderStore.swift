import Foundation
import UserNotifications

/// Generic reminders beyond anniversaries (renewals, bills, one-shots).
struct AppReminder: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var notes: String
    var dueAt: Date
    var notify: Bool
    var createdAt: Date

    var daysLeft: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: dueAt)
        ).day ?? 0
    }
}

@MainActor
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()
    private let fileName = "app_reminders.json"

    @Published private(set) var items: [AppReminder] = []

    private init() {
        items = LocalJSONStore.load([AppReminder].self, from: fileName, fallback: [])
        sort()
    }

    private func persist() {
        LocalJSONStore.save(items, to: fileName)
    }

    private func sort() {
        items.sort { $0.dueAt < $1.dueAt }
    }

    func upsert(_ item: AppReminder) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
        }
        sort()
        persist()
        if item.notify {
            scheduleNotification(for: item)
        }
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["reminder.\(id)"])
    }

    var upcoming: [AppReminder] {
        items.filter { $0.daysLeft >= 0 }.prefix(20).map { $0 }
    }

    private func scheduleNotification(for item: AppReminder) {
        let content = UNMutableNotificationContent()
        content.title = "提醒：\(item.title)"
        content.body = item.notes.isEmpty ? "到期日 \(item.dueAt.formatted(date: .abbreviated, time: .omitted))" : item.notes
        content.sound = .default

        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.dueAt)
        if comps.hour == nil { comps.hour = 9; comps.minute = 0 }
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: "reminder.\(item.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
