import Foundation

/// Session + external mail API client.
/// - Session path: cookie login with **single-flight** `ensureSession` and **at most one** re-login on 401.
/// - 429 `LOGIN_RATE_LIMITED`: surface server message; **never** auto-retry.
actor MailService {
    static let shared = MailService()
    private let client = NetworkClient.shared
    private var sessionLoggedIn = false
    /// In-flight login shared by concurrent `ensureSession` callers (Settings probe + Mail tab).
    private var loginTask: Task<Void, Error>?

    // MARK: - Session auth

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
        if http.statusCode == 401 {
            throw Self.parseLoginFailure(data: data, fallback: NetworkError.unauthorized)
        }
        // Rate-limited login: do not retry; expose server remaining-seconds message.
        if http.statusCode == 429 {
            throw Self.parseLoginFailure(
                data: data,
                fallback: NetworkError.message("登录过于频繁，请稍后重试")
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.parseLoginFailure(
                data: data,
                fallback: NetworkClient.httpError(status: http.statusCode, body: data)
            )
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = obj["success"] as? Bool, success == false {
            let msg = Self.errorMessage(from: obj) ?? "登录失败"
            throw NetworkError.message(msg)
        }
        sessionLoggedIn = true
    }

    /// Ensures a valid session. Concurrent callers share one login Task (single-flight).
    /// Skips network if `sessionLoggedIn` is already true.
    func ensureSession(baseURL: String, password: String) async throws {
        if sessionLoggedIn { return }
        if let existing = loginTask {
            try await existing.value
            return
        }
        let task = Task {
            try await self.login(baseURL: baseURL, password: password)
        }
        loginTask = task
        do {
            try await task.value
            loginTask = nil
        } catch {
            loginTask = nil
            throw error
        }
    }

    /// Clears local session flag. Call with `NetworkClient.clearCookies()` on logout-all.
    func logout() {
        sessionLoggedIn = false
        loginTask?.cancel()
        loginTask = nil
    }

    /// Run a cookie-authenticated request with at most one re-login on 401.
    /// 429 / other errors propagate without retry.
    func withSessionRetry<T>(
        baseURL: String,
        password: String,
        _ work: () async throws -> T
    ) async throws -> T {
        try await ensureSession(baseURL: baseURL, password: password)
        do {
            return try await work()
        } catch NetworkError.unauthorized {
            sessionLoggedIn = false
            // Force a single re-login (does not recurse through withSessionRetry).
            try await login(baseURL: baseURL, password: password)
            return try await work()
        }
    }

    // MARK: - Session API

    /// Paginated accounts. Default page=1, page_size=50 (server max 100).
    func listAccounts(
        baseURL: String,
        password: String,
        page: Int = 1,
        pageSize: Int = 50
    ) async throws -> MailAccountsPage {
        try await withSessionRetry(baseURL: baseURL, password: password) {
            let (data, http) = try await self.client.data(
                base: baseURL,
                path: "/api/accounts",
                headers: ["Accept": "application/json"],
                query: [
                    .init(name: "page", value: String(max(1, page))),
                    .init(name: "page_size", value: String(min(100, max(1, pageSize))))
                ],
                useCookies: true
            )
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkClient.httpError(status: http.statusCode, body: data)
            }
            let root = try JSONSerialization.jsonObject(with: data)
            return MailJSONHelper.parseAccountsPage(root, requestedPage: page, pageSize: pageSize)
        }
    }

    func listMessages(
        baseURL: String,
        password: String,
        email: String,
        folder: String = "inbox",
        skip: Int = 0,
        top: Int = 30
    ) async throws -> MailMessagesPage {
        try await withSessionRetry(baseURL: baseURL, password: password) {
            let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
            let (data, http) = try await self.client.data(
                base: baseURL,
                path: "/api/emails/\(encoded)",
                headers: ["Accept": "application/json"],
                query: [
                    .init(name: "folder", value: folder),
                    .init(name: "skip", value: String(max(0, skip))),
                    .init(name: "top", value: String(max(1, top)))
                ],
                useCookies: true
            )
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkClient.httpError(status: http.statusCode, body: data)
            }
            let root = try JSONSerialization.jsonObject(with: data)
            return MailJSONHelper.parseMessagesPage(root, requestedTop: top)
        }
    }

    func messageDetail(
        baseURL: String,
        password: String,
        email: String,
        messageID: String
    ) async throws -> MailMessage {
        try await withSessionRetry(baseURL: baseURL, password: password) {
            let emailEnc = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
            let idEnc = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageID
            let (data, http) = try await self.client.data(
                base: baseURL,
                path: "/api/email/\(emailEnc)/\(idEnc)",
                headers: ["Accept": "application/json"],
                useCookies: true
            )
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkClient.httpError(status: http.statusCode, body: data)
            }
            let root = try JSONSerialization.jsonObject(with: data)
            if let detail = MailJSONHelper.parseMessageDetail(root) { return detail }
            throw NetworkError.message("无法解析邮件详情")
        }
    }

    // MARK: - External API (X-API-Key) — partial; full UX in PR-5b

    func externalMessages(
        baseURL: String,
        apiKey: String,
        email: String,
        folder: String = "inbox",
        skip: Int = 0,
        top: Int = 30
    ) async throws -> MailMessagesPage {
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
                .init(name: "skip", value: String(max(0, skip))),
                .init(name: "top", value: String(max(1, min(50, top))))
            ]
        )
        if http.statusCode == 401 || http.statusCode == 403 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        let root = try JSONSerialization.jsonObject(with: data)
        return MailJSONHelper.parseMessagesPage(root, requestedTop: top)
    }

    func externalMessageDetail(
        baseURL: String,
        apiKey: String,
        email: String,
        messageID: String,
        folder: String = "inbox"
    ) async throws -> MailMessage {
        let idEnc = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageID
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/external/messages/\(idEnc)",
            headers: [
                "X-API-Key": apiKey,
                "Accept": "application/json"
            ],
            query: [
                .init(name: "email", value: email),
                .init(name: "folder", value: folder)
            ]
        )
        if http.statusCode == 401 || http.statusCode == 403 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
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

    // MARK: - Login error parsing

    private static func errorMessage(from obj: [String: Any]) -> String? {
        if let err = obj["error"] as? [String: Any] {
            if let msg = err["message"] as? String, !msg.isEmpty { return msg }
        }
        if let msg = obj["message"] as? String, !msg.isEmpty { return msg }
        return nil
    }

    private static func parseLoginFailure(data: Data, fallback: NetworkError) -> NetworkError {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = errorMessage(from: obj), !msg.isEmpty else {
            return fallback
        }
        return .message(msg)
    }
}
