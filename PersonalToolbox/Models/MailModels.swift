import Foundation

struct MailAccount: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let email: String
    let status: String?
    let provider: String?
    let remark: String?

    init(id: String? = nil, email: String, status: String? = nil, provider: String? = nil, remark: String? = nil) {
        self.id = id ?? email
        self.email = email
        self.status = status
        self.provider = provider
        self.remark = remark
    }
}

struct MailMessage: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let subject: String
    let from: String
    let to: String?
    let preview: String
    let body: String?
    let htmlBody: String?
    let receivedAt: String?
    let folder: String?

    var displayDate: String {
        if let date = parsedDate {
            return MailJSONHelper.displayFormatter.string(from: date)
        }
        return receivedAt ?? ""
    }

    /// Parsed receive time when the API string is recognizable.
    var parsedDate: Date? {
        MailJSONHelper.parseDate(receivedAt)
    }

    /// Heuristic 4–8 digit verification code from subject/body/preview/HTML-stripped body.
    var extractedVerificationCode: String? {
        var parts = [subject, body, preview].compactMap { $0 }
        if let html = htmlBody, !html.isEmpty {
            parts.append(MailJSONHelper.stripTags(html))
        }
        return MailJSONHelper.extractVerificationCode(from: parts.joined(separator: "\n"))
    }
}

/// Paginated account list from `GET /api/accounts`.
struct MailAccountsPage: Sendable {
    let accounts: [MailAccount]
    let page: Int
    let pageSize: Int
    let totalCount: Int?
    let totalPages: Int?
    let hasMore: Bool
}

/// Message list page from session or external list endpoints.
struct MailMessagesPage: Sendable {
    let messages: [MailMessage]
    let hasMore: Bool
}

enum MailJSONHelper {
    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let d = isoFractional.date(from: raw) { return d }
        if let d = isoBasic.date(from: raw) { return d }
        // Common fallbacks (local formatter — DateFormatter is not thread-safe to share mutably).
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss"
        ] {
            df.dateFormat = format
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }

    static func extractVerificationCode(from text: String) -> String? {
        // Prefer phrases near 验证码 / code, then bare 4–8 digit tokens.
        let patterns = [
            #"验证码[是为:：\s]*([0-9]{4,8})"#,
            #"(?:code|Code|CODE)[:\s]*([0-9]{4,8})"#,
            #"\b([0-9]{6})\b"#,
            #"\b([0-9]{4,8})\b"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    static func string(_ any: Any?, keys: [String]) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let n = dict[key] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    static func intValue(_ any: Any?, keys: [String]) -> Int? {
        guard let dict = any as? [String: Any] else { return nil }
        for key in keys {
            if let n = dict[key] as? Int { return n }
            if let n = dict[key] as? NSNumber { return n.intValue }
            if let s = dict[key] as? String, let n = Int(s) { return n }
        }
        return nil
    }

    static func boolValue(_ any: Any?, keys: [String]) -> Bool? {
        guard let dict = any as? [String: Any] else { return nil }
        for key in keys {
            if let b = dict[key] as? Bool { return b }
            if let n = dict[key] as? NSNumber { return n.boolValue }
            if let s = dict[key] as? String {
                let lower = s.lowercased()
                if lower == "true" || lower == "1" { return true }
                if lower == "false" || lower == "0" { return false }
            }
        }
        return nil
    }

    static func array(_ any: Any?, keys: [String]) -> [[String: Any]] {
        guard let dict = any as? [String: Any] else {
            if let arr = any as? [[String: Any]] { return arr }
            return []
        }
        for key in keys {
            if let arr = dict[key] as? [[String: Any]] { return arr }
            if let arr = dict[key] as? [Any] {
                return arr.compactMap { $0 as? [String: Any] }
            }
        }
        // nested data
        if let data = dict["data"] {
            let nested = array(data, keys: keys)
            if !nested.isEmpty { return nested }
            if let dataDict = data as? [String: Any] {
                for key in keys {
                    if let arr = dataDict[key] as? [[String: Any]] { return arr }
                }
            }
        }
        return []
    }

    static func parseAccounts(_ root: Any) -> [MailAccount] {
        parseAccountsPage(root, requestedPage: 1, pageSize: 50).accounts
    }

    static func parseAccountsPage(_ root: Any, requestedPage: Int, pageSize: Int) -> MailAccountsPage {
        let rows = array(root, keys: ["accounts", "items", "list", "data"])
        let accounts = rows.compactMap { row -> MailAccount? in
            guard let email = string(row, keys: ["email", "email_address", "address", "mail"]) else { return nil }
            let id = string(row, keys: ["id", "account_id"]) ?? email
            return MailAccount(
                id: id,
                email: email,
                status: string(row, keys: ["status"]),
                provider: string(row, keys: ["provider", "account_type"]),
                remark: string(row, keys: ["remark", "note", "name"])
            )
        }

        var page = requestedPage
        var size = pageSize
        var totalCount: Int?
        var totalPages: Int?

        if let dict = root as? [String: Any] {
            let pagination = dict["pagination"] as? [String: Any]
            let source: [String: Any] = pagination ?? dict
            if let p = intValue(source, keys: ["page"]) { page = p }
            if let s = intValue(source, keys: ["page_size", "pageSize", "per_page"]) { size = s }
            totalCount = intValue(source, keys: ["total_count", "total", "totalCount", "count"])
            totalPages = intValue(source, keys: ["total_pages", "totalPages", "pages"])
            if totalPages == nil, let total = totalCount, size > 0 {
                totalPages = total == 0 ? 0 : (total + size - 1) / size
            }
        }

        let hasMore: Bool
        if let pages = totalPages {
            hasMore = page < pages
        } else if let total = totalCount {
            hasMore = page * size < total
        } else {
            // No pagination meta: more pages only if this page looks full.
            hasMore = accounts.count >= size
        }

        return MailAccountsPage(
            accounts: accounts,
            page: page,
            pageSize: size,
            totalCount: totalCount,
            totalPages: totalPages,
            hasMore: hasMore
        )
    }

    static func parseMessages(_ root: Any) -> [MailMessage] {
        parseMessagesPage(root, requestedTop: 30).messages
    }

    static func parseMessagesPage(_ root: Any, requestedTop: Int) -> MailMessagesPage {
        let rows = array(root, keys: ["emails", "messages", "items", "list", "data"])
        let messages = rows.compactMap { row -> MailMessage? in mapMessage(row) }

        var hasMore = false
        if let dict = root as? [String: Any] {
            if let flag = boolValue(dict, keys: ["has_more", "hasMore"]) {
                hasMore = flag
            } else {
                hasMore = messages.count >= requestedTop
            }
        } else {
            hasMore = messages.count >= requestedTop
        }
        return MailMessagesPage(messages: messages, hasMore: hasMore)
    }

    static func parseMessageDetail(_ root: Any) -> MailMessage? {
        let dict: [String: Any]
        if let d = root as? [String: Any] {
            if let data = d["data"] as? [String: Any] {
                dict = data
            } else if let email = d["email"] as? [String: Any] {
                // Session Graph detail: { success, email: { id, body, body_type, ... } }
                dict = email
            } else if let message = d["message"] as? [String: Any] {
                dict = message
            } else {
                dict = d
            }
        } else {
            return nil
        }
        return mapMessage(dict)
    }

    private static func mapMessage(_ row: [String: Any]) -> MailMessage? {
        let id = string(row, keys: ["id", "message_id", "messageId"]) ?? UUID().uuidString
        let subject = string(row, keys: ["subject", "title"]) ?? "(无主题)"
        let from = string(row, keys: ["from", "from_address", "fromAddress", "sender"]) ?? ""
        let to = string(row, keys: ["to", "to_address", "toAddress"])

        // Graph session detail uses body + body_type; external uses content / html_content.
        let bodyType = (string(row, keys: ["body_type", "bodyType", "contentType"]) ?? "").lowercased()
        let rawBody = string(row, keys: ["content", "body", "text", "text_content", "body_text"])
        let rawHtml = string(row, keys: ["html_content", "html", "htmlBody", "body_html", "bodyHtml"])

        let body: String?
        let html: String?
        if bodyType == "html" {
            html = rawHtml ?? rawBody
            body = string(row, keys: ["content", "text", "text_content", "body_text"])
                ?? stripTags(html ?? "")
        } else if bodyType == "text" {
            body = rawBody
            html = rawHtml
        } else {
            body = rawBody
            html = rawHtml
        }

        let preview = string(row, keys: ["preview", "snippet", "summary", "body_preview", "bodyPreview", "content_preview"])
            ?? String((body ?? html ?? "").prefix(120))
        let received = string(row, keys: ["timestamp", "created_at", "receivedDateTime", "date", "received_at", "receivedAt"])
        let folder = string(row, keys: ["folder"])
        return MailMessage(
            id: id,
            subject: subject,
            from: from,
            to: to,
            preview: preview,
            body: body,
            htmlBody: html,
            receivedAt: received,
            folder: folder
        )
    }

    /// Very small tag strip for HTML→plain fallback (not a full HTML parser).
    static func stripTags(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        var result = html
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        return result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
