import Foundation
import UIKit

/// Payload passed from Share Extension → host app.
/// Prefer pasteboard + URL scheme so Ad Hoc profiles need no App Group entitlement.
struct ShareHandoffPayload: Codable, Equatable {
    var text: String
    var urls: [String]
    var createdAt: TimeInterval

    var combinedText: String {
        var parts: [String] = []
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { parts.append(t) }
        for u in urls where !parts.contains(u) { parts.append(u) }
        return parts.joined(separator: "\n")
    }
}

enum ShareHandoff {
    static let appGroupId = "group.app.parsnip6345.lake8262"
    static let payloadKey = "pendingSharePayload"
    static let pasteboardName = "xinstool.share.payload"
    static let urlScheme = "xinstool"
    static let openHost = "share"

    static var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func save(_ payload: ShareHandoffPayload) {
        // 1) App Group (when entitlements allow)
        if let data = try? JSONEncoder().encode(payload) {
            groupDefaults?.set(data, forKey: payloadKey)
            groupDefaults?.synchronize()
        }
        // 2) Named pasteboard fallback (always works cross-process on device)
        if let data = try? JSONEncoder().encode(payload) {
            let pb = UIPasteboard(name: UIPasteboard.Name(pasteboardName), create: true)
            pb?.setData(data, forPasteboardType: "public.data")
        }
        // 3) General pasteboard text for Quick Actions prefill
        let combined = payload.combinedText
        if !combined.isEmpty {
            UIPasteboard.general.string = combined
        }
    }

    static func consume() -> ShareHandoffPayload? {
        if let data = groupDefaults?.data(forKey: payloadKey),
           let payload = try? JSONDecoder().decode(ShareHandoffPayload.self, from: data) {
            groupDefaults?.removeObject(forKey: payloadKey)
            groupDefaults?.synchronize()
            clearNamedPasteboard()
            return payload
        }
        if let pb = UIPasteboard(name: UIPasteboard.Name(pasteboardName), create: false),
           let data = pb.data(forPasteboardType: "public.data"),
           let payload = try? JSONDecoder().decode(ShareHandoffPayload.self, from: data) {
            clearNamedPasteboard()
            return payload
        }
        // Last resort: general pasteboard text
        if let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return ShareHandoffPayload(text: s, urls: [], createdAt: Date().timeIntervalSince1970)
        }
        return nil
    }

    private static func clearNamedPasteboard() {
        UIPasteboard.remove(withName: UIPasteboard.Name(pasteboardName))
    }

    static func openURL(with payload: ShareHandoffPayload) -> URL? {
        save(payload)
        var c = URLComponents()
        c.scheme = urlScheme
        c.host = openHost
        c.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        return c.url
    }

    static func isShareURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == urlScheme && url.host?.lowercased() == openHost
    }
}
