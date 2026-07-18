import Foundation

struct MailAccount: Identifiable, Hashable, Codable {
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

struct MailMessage: Identifiable, Hashable, Codable {
    let id: String
    let subject: String
    let from: String
    let to: String?
    let preview: String
    let body: String?
    let htmlBody: String?
    let receivedAt: String?
    let folder: String?

    var displayDate: String { receivedAt ?? "" }
}

enum MailJSONHelper {
    static func string(_ any: Any?, keys: [String]) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let n = dict[key] as? NSNumber { return n.stringValue }
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
        let rows = array(root, keys: ["accounts", "items", "list", "data"])
        return rows.compactMap { row in
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
    }

    static func parseMessages(_ root: Any) -> [MailMessage] {
        let rows = array(root, keys: ["emails", "messages", "items", "list", "data"])
        return rows.compactMap { row -> MailMessage? in
            let id = string(row, keys: ["id", "message_id", "messageId"]) ?? UUID().uuidString
            let subject = string(row, keys: ["subject", "title"]) ?? "(无主题)"
            let from = string(row, keys: ["from", "from_address", "fromAddress", "sender"]) ?? ""
            let to = string(row, keys: ["to", "to_address", "toAddress"])
            let body = string(row, keys: ["content", "body", "text", "text_content"])
            let html = string(row, keys: ["html_content", "html", "htmlBody"])
            let preview = string(row, keys: ["preview", "snippet", "summary"])
                ?? String((body ?? html ?? "").prefix(120))
            let received = string(row, keys: ["timestamp", "created_at", "receivedDateTime", "date", "received_at"])
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
    }

    static func parseMessageDetail(_ root: Any) -> MailMessage? {
        let dict: [String: Any]
        if let d = root as? [String: Any] {
            if let data = d["data"] as? [String: Any] {
                dict = data
            } else {
                dict = d
            }
        } else {
            return nil
        }
        let list = parseMessages([dict])
        return list.first
    }
}
