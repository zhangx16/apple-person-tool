import Foundation
import SwiftUI

// MARK: - 财联社电报 (aligned with riccilnl 财联社.scripting)

struct CLSNewsItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var summary: String
    var pubDate: String
    var source: String

    var displayText: String {
        let base = summary.isEmpty ? title : summary
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var timeLabel: String {
        CLSNewsParsing.formatTime(pubDate)
    }
}

struct CLSNewsCache: Codable, Sendable {
    var items: [CLSNewsItem]
    var lastUpdated: Date
    var sourceURL: String
}

enum CLSAccent {
    /// Match script color rgba(28, 140, 255)
    static let color = Color(hex: 0x1C8CFF)
}

enum CLSNewsParsing {
    static let defaultFeedURL = "https://pyrsshub.vercel.app/cls/telegraph/"

    static func formatTime(_ dateStr: String) -> String {
        // Try ISO8601 first
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: dateStr) {
            return clock(d)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: dateStr) {
            return clock(d)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let d = f.date(from: dateStr) {
            return clock(d)
        }
        if let d = Date(dateStr) {
            return clock(d)
        }
        return "--:--"
    }

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let map: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&nbsp;", " ")
        ]
        // Order: &amp; last after others would double-decode wrong; decode amp first is wrong for &lt;
        // Standard: replace named entities without amp first, then amp
        for (k, v) in map where k != "&amp;" {
            result = result.replacingOccurrences(of: k, with: v)
        }
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        // numeric entities
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            var mutable = result
            for m in matches {
                guard m.numberOfRanges >= 2,
                      let full = Range(m.range(at: 0), in: mutable),
                      let numR = Range(m.range(at: 1), in: mutable),
                      let code = Int(mutable[numR]),
                      let scalar = UnicodeScalar(code) else { continue }
                mutable.replaceSubrange(full, with: String(Character(scalar)))
            }
            result = mutable
        }
        return result
    }

    static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove「财联社x月x日电，」prefix
    static func filterTelegraphPrefix(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^财联社\S+月\S+日电，\s*"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    static func cleanText(_ raw: String) -> String {
        filterTelegraphPrefix(decodeHTMLEntities(stripHTML(raw)))
    }

    /// Parse Atom-ish RSS from pyrsshub cls/telegraph
    static func parseFeedXML(_ text: String) -> [CLSNewsItem] {
        var items: [CLSNewsItem] = []
        guard let entryRegex = try? NSRegularExpression(
            pattern: #"<entry[^>]*>([\s\S]*?)</entry>"#,
            options: [.caseInsensitive]
        ) else { return [] }

        let ns = text as NSString
        let matches = entryRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let entry = ns.substring(with: m.range(at: 1))
            let title = extractTag(entry, names: ["title"])
            let content = extractTag(entry, names: ["content", "summary", "description"])
            let pubDate = extractTag(entry, names: ["published", "pubDate", "updated"])
            let cleanedTitle = cleanText(title)
            let cleanedSummary = cleanText(content)
            guard !cleanedTitle.isEmpty || !cleanedSummary.isEmpty else { continue }
            let id = "\(cleanedTitle)|\(pubDate)"
            items.append(
                CLSNewsItem(
                    id: id,
                    title: cleanedTitle,
                    summary: cleanedSummary,
                    pubDate: pubDate,
                    source: "财联社"
                )
            )
        }

        // Fallback: RSS 2.0 <item>
        if items.isEmpty, let itemRegex = try? NSRegularExpression(
            pattern: #"<item[^>]*>([\s\S]*?)</item>"#,
            options: [.caseInsensitive]
        ) {
            let itemMatches = itemRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in itemMatches {
                guard m.numberOfRanges >= 2 else { continue }
                let entry = ns.substring(with: m.range(at: 1))
                let title = extractTag(entry, names: ["title"])
                let content = extractTag(entry, names: ["description", "content:encoded", "content"])
                let pubDate = extractTag(entry, names: ["pubDate", "published"])
                let cleanedTitle = cleanText(title)
                let cleanedSummary = cleanText(content)
                guard !cleanedTitle.isEmpty || !cleanedSummary.isEmpty else { continue }
                items.append(
                    CLSNewsItem(
                        id: "\(cleanedTitle)|\(pubDate)",
                        title: cleanedTitle,
                        summary: cleanedSummary,
                        pubDate: pubDate,
                        source: "财联社"
                    )
                )
            }
        }

        return Array(items.prefix(50))
    }

    private static func extractTag(_ xml: String, names: [String]) -> String {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            // CDATA or plain
            let pattern = #"<\#(escaped)[^>]*>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?</\#(escaped)>"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let m = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: xml) {
                return String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }
}

// Helper for loose date parse
private extension Date {
    init?(_ string: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss"
        ] {
            f.dateFormat = format
            if let d = f.date(from: string) {
                self = d
                return
            }
        }
        return nil
    }
}
