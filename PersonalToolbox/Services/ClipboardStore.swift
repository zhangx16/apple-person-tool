import Foundation
import UIKit

struct ClipboardItem: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var createdAt: Date
    var source: String

    var preview: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 120 ? String(t.prefix(120)) + "…" : t
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()
    private let fileName = "clipboard_history.json"
    private let maxItems = 100

    @Published private(set) var items: [ClipboardItem] = []

    private init() {
        items = LocalJSONStore.load([ClipboardItem].self, from: fileName, fallback: [])
    }

    private func persist() {
        LocalJSONStore.save(items, to: fileName)
    }

    /// Capture current system pasteboard if new.
    @discardableResult
    func capturePasteboard() -> ClipboardItem? {
        #if canImport(UIKit)
        guard let text = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        if items.first?.text == text { return items.first }
        let item = ClipboardItem(
            id: UUID().uuidString,
            text: text,
            createdAt: Date(),
            source: "pasteboard"
        )
        items.insert(item, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        persist()
        return item
        #else
        return nil
        #endif
    }

    func addManual(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let item = ClipboardItem(id: UUID().uuidString, text: t, createdAt: Date(), source: "manual")
        items.insert(item, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
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

    func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
