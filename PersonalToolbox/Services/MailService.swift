import Foundation

actor MailService {
    static let shared = MailService()
    private let client = NetworkClient.shared
    private var sessionLoggedIn = false

    func login(baseURL: String, password: String) async throws {
        struct Body: Encodable { let password: String }
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/login",
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: try JSONEncoder().encode(Body(password: password)),
            useCookies: true
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = obj["success"] as? Bool, success == false {
            let msg = (obj["error"] as? [String: Any])?["message"] as? String
            throw NetworkError.message(msg ?? "登录失败")
        }
        sessionLoggedIn = true
    }

    func ensureSession(baseURL: String, password: String) async throws {
        if sessionLoggedIn { return }
        try await login(baseURL: baseURL, password: password)
    }

    func listAccounts(baseURL: String, password: String) async throws -> [MailAccount] {
        try await ensureSession(baseURL: baseURL, password: password)
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/accounts",
            headers: ["Accept": "application/json"],
            useCookies: true
        )
        if http.statusCode == 401 {
            sessionLoggedIn = false
            try await login(baseURL: baseURL, password: password)
            return try await listAccounts(baseURL: baseURL, password: password)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let root = try JSONSerialization.jsonObject(with: data)
        return MailJSONHelper.parseAccounts(root)
    }

    func listMessages(
        baseURL: String,
        password: String,
        email: String,
        folder: String = "inbox",
        skip: Int = 0,
        top: Int = 30
    ) async throws -> [MailMessage] {
        try await ensureSession(baseURL: baseURL, password: password)
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/emails/\(encoded)",
            headers: ["Accept": "application/json"],
            query: [
                .init(name: "folder", value: folder),
                .init(name: "skip", value: String(skip)),
                .init(name: "top", value: String(top))
            ],
            useCookies: true
        )
        if http.statusCode == 401 {
            sessionLoggedIn = false
            try await login(baseURL: baseURL, password: password)
            return try await listMessages(baseURL: baseURL, password: password, email: email, folder: folder, skip: skip, top: top)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let root = try JSONSerialization.jsonObject(with: data)
        return MailJSONHelper.parseMessages(root)
    }

    func messageDetail(
        baseURL: String,
        password: String,
        email: String,
        messageID: String
    ) async throws -> MailMessage {
        try await ensureSession(baseURL: baseURL, password: password)
        let emailEnc = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
        let idEnc = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageID
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/email/\(emailEnc)/\(idEnc)",
            headers: ["Accept": "application/json"],
            useCookies: true
        )
        if http.statusCode == 401 {
            sessionLoggedIn = false
            try await login(baseURL: baseURL, password: password)
            return try await messageDetail(baseURL: baseURL, password: password, email: email, messageID: messageID)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let root = try JSONSerialization.jsonObject(with: data)
        if let detail = MailJSONHelper.parseMessageDetail(root) { return detail }
        throw NetworkError.message("无法解析邮件详情")
    }

    // External API path (X-API-Key) — good for single-email workflows
    func externalMessages(
        baseURL: String,
        apiKey: String,
        email: String,
        folder: String = "inbox",
        top: Int = 30
    ) async throws -> [MailMessage] {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/external/messages",
            headers: [
                "X-API-Key": apiKey,
                "Accept": "application/json"
            ],
            query: [
                .init(name: "email", value: email),
                .init(name: "folder", value: folder),
                .init(name: "top", value: String(top))
            ]
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let root = try JSONSerialization.jsonObject(with: data)
        return MailJSONHelper.parseMessages(root)
    }

    func externalMessageDetail(
        baseURL: String,
        apiKey: String,
        messageID: String
    ) async throws -> MailMessage {
        let idEnc = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageID
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/external/messages/\(idEnc)",
            headers: [
                "X-API-Key": apiKey,
                "Accept": "application/json"
            ]
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let root = try JSONSerialization.jsonObject(with: data)
        if let detail = MailJSONHelper.parseMessageDetail(root) { return detail }
        throw NetworkError.message("无法解析邮件详情")
    }

    func externalHealth(baseURL: String, apiKey: String) async throws -> Bool {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/external/health",
            headers: ["X-API-Key": apiKey]
        )
        return (200..<300).contains(http.statusCode) && !data.isEmpty
    }
}
