import Foundation

/// Lightweight “watch later” queue for video / media links.
struct WatchLaterItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var url: String
    var source: String
    var createdAt: Date
}

@MainActor
final class WatchLaterStore: ObservableObject {
    static let shared = WatchLaterStore()
    private let fileName = "watchLater.json"

    @Published private(set) var items: [WatchLaterItem] = []

    private init() {
        items = LocalJSONStore.load([WatchLaterItem].self, from: fileName, fallback: [])
        items.sort { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        LocalJSONStore.save(items, to: fileName)
    }

    func add(url: String, title: String = "", source: String = "") {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        if let i = items.firstIndex(where: { $0.url == u }) {
            items[i].createdAt = Date()
            if !title.isEmpty { items[i].title = title }
        } else {
            items.insert(
                WatchLaterItem(
                    id: UUID().uuidString,
                    title: title.isEmpty ? u : title,
                    url: u,
                    source: source,
                    createdAt: Date()
                ),
                at: 0
            )
        }
        if items.count > 100 {
            items = Array(items.prefix(100))
        }
        persist()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        items = []
        persist()
    }
}
