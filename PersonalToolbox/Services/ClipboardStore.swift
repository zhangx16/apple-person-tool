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

    enum Kind: String {
        case url, tracking, cookie, code, plain
        var title: String {
            switch self {
            case .url: return "链接"
            case .tracking: return "单号"
            case .cookie: return "Cookie"
            case .code: return "验证码"
            case .plain: return "文本"
            }
        }
        var systemImage: String {
            switch self {
            case .url: return "link"
            case .tracking: return "shippingbox"
            case .cookie: return "key"
            case .code: return "number"
            case .plain: return "doc.plaintext"
            }
        }
    }

    var kind: Kind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://")
            || t.contains("b23.tv") || t.contains("bilibili.com") {
            return .url
        }
        if t.lowercased().contains("session") || t.lowercased().contains("cookie")
            || (t.contains("=") && t.contains(";") && t.count > 20) {
            return .cookie
        }
        if let _ = ActionRouter.extractVerificationCode(from: t), t.count <= 12 {
            return .code
        }
        // Tracking-ish: long alphanumeric
        let alnum = t.replacingOccurrences(of: " ", with: "")
        if alnum.count >= 10, alnum.count <= 32, alnum.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil {
            return .tracking
        }
        return .plain
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
