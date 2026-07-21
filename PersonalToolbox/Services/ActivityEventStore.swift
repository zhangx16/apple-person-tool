import Foundation

/// Lightweight local activity feed for Overview「今日动态」.
struct ActivityEvent: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var tintHex: UInt32
    var createdAt: Date
    /// Optional deep-link key: checkin / health / download / notes …
    var route: String?

    static func make(
        title: String,
        subtitle: String,
        systemImage: String,
        tintHex: UInt32 = 0x0A84FF,
        route: String? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            id: UUID().uuidString,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tintHex: tintHex,
            createdAt: Date(),
            route: route
        )
    }
}

@MainActor
final class ActivityEventStore: ObservableObject {
    static let shared = ActivityEventStore()
    private let fileName = "activity_events.json"
    private let maxItems = 80

    @Published private(set) var events: [ActivityEvent] = []

    private init() {
        events = LocalJSONStore.load([ActivityEvent].self, from: fileName, fallback: [])
    }

    private func persist() {
        LocalJSONStore.save(events, to: fileName)
    }

    func log(_ event: ActivityEvent) {
        // Dedupe identical title+subtitle within 2 minutes.
        if let first = events.first,
           first.title == event.title,
           first.subtitle == event.subtitle,
           Date().timeIntervalSince(first.createdAt) < 120 {
            return
        }
        events.insert(event, at: 0)
        if events.count > maxItems {
            events = Array(events.prefix(maxItems))
        }
        persist()
    }

    func clear() {
        events = []
        persist()
    }

    var today: [ActivityEvent] {
        let cal = Calendar.current
        return events.filter { cal.isDateInToday($0.createdAt) }
    }

    var recent: [ActivityEvent] {
        Array(events.prefix(12))
    }
}
