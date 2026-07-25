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

    // MARK: - Komari import

    /// Stable id for a Komari node subscription line.
    static func komariSubscriptionId(uuid: String) -> String {
        "komari-\(uuid)"
    }

    /// Import / update bills from Komari nodes that have price information.
    /// Format: name · amount · currency · nextDue from expiredAt · notes with region/group.
    @discardableResult
    func importFromKomariNodes(_ nodes: [KomariNode], replaceExisting: Bool = false) -> Int {
        var count = 0
        for node in nodes {
            guard let price = node.price, price > 0 else { continue }
            let id = Self.komariSubscriptionId(uuid: node.uuid)
            if !replaceExisting, items.contains(where: { $0.id == id }) {
                // still refresh amount / due
            }
            let currency = (node.currency?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "CNY"
            let due: Date
            if let exp = node.expiredAt, let d = KomariTime.parse(exp) {
                due = d
            } else {
                due = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            }
            var notesParts: [String] = ["来源: Komari"]
            if let region = node.region, !region.isEmpty { notesParts.append("地区 \(region)") }
            if let group = node.group, !group.isEmpty { notesParts.append("分组 \(group)") }
            if let virt = node.virtualization, !virt.isEmpty { notesParts.append(virt) }
            if let traffic = node.trafficLimit, traffic > 0 {
                notesParts.append("流量上限 \(ByteCountFormatter.string(fromByteCount: traffic, countStyle: .binary))")
            }

            let item = SubscriptionItem(
                id: id,
                name: "VPS · \(node.displayName)",
                amount: price,
                currency: currency.uppercased(),
                cycle: "monthly",
                nextDue: due,
                notes: notesParts.joined(separator: " · "),
                url: "",
                createdAt: items.first(where: { $0.id == id })?.createdAt ?? Date()
            )
            upsert(item)
            count += 1
        }
        return count
    }
}
