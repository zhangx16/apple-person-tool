import Foundation

struct SubscriptionItem: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var amount: Double
    var currency: String
    var cycle: String // monthly / yearly / once
    var nextDue: Date
    var notes: String
    var url: String
    var createdAt: Date

    var cycleTitle: String {
        switch cycle {
        case "yearly": return "年付"
        case "once": return "一次性"
        default: return "月付"
        }
    }

    var daysUntilDue: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: nextDue)).day ?? 0
    }
}

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()
    private let fileName = "subscriptions.json"

    @Published private(set) var items: [SubscriptionItem] = []

    private init() {
        items = LocalJSONStore.load([SubscriptionItem].self, from: fileName, fallback: [])
        sort()
    }

    private func persist() {
        LocalJSONStore.save(items, to: fileName)
    }

    private func sort() {
        items.sort { $0.nextDue < $1.nextDue }
    }

    func upsert(_ item: SubscriptionItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
        }
        sort()
        persist()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    var dueSoon: [SubscriptionItem] {
        items.filter { $0.daysUntilDue <= 14 }
    }

    var monthTotal: Double {
        items.reduce(0) { partial, item in
            switch item.cycle {
            case "yearly": return partial + item.amount / 12
            case "once": return partial
            default: return partial + item.amount
            }
        }
    }
}
