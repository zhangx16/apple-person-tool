import Foundation

/// Client for glados-checkin-web mobile API (`/api/v1/*`).
actor CheckinService {
    static let shared = CheckinService()
    private let client = NetworkClient.shared

    private func normalizedToken(_ apiToken: String) -> String {
        apiToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: "")
    }

    private func headers(apiToken: String) -> [String: String] {
        let token = normalizedToken(apiToken)
        return [
            "Authorization": "Bearer \(token)",
            "X-API-Key": token,
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
    }

    private func normalizedBase(_ baseURL: String) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    private func requestData(
        baseURL: String,
        apiToken: String,
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        let (data, http) = try await client.data(
            base: normalizedBase(baseURL),
            path: path,
            method: method,
            headers: headers(apiToken: apiToken),
            body: body
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            // Prefer server `{error: "..."}` message.
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String, !err.isEmpty {
                throw NetworkError.message(err)
            }
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        return data
    }

    func health(baseURL: String, apiToken: String) async throws -> CheckinHealth {
        let data = try await requestData(baseURL: baseURL, apiToken: apiToken, path: "/api/v1/health")
        return try JSONDecoder().decode(CheckinHealth.self, from: data)
    }

    func summary(baseURL: String, apiToken: String) async throws -> CheckinSummary {
        let data = try await requestData(baseURL: baseURL, apiToken: apiToken, path: "/api/v1/summary")
        do {
            return try JSONDecoder().decode(CheckinSummary.self, from: data)
        } catch {
            let preview = String(data: data.prefix(180), encoding: .utf8) ?? ""
            throw NetworkError.message("签到数据解析失败：\(error.localizedDescription)。\(preview)")
        }
    }

    // MARK: - Website accounts

    func getAccount(baseURL: String, apiToken: String, id: String) async throws -> CheckinAccountDetail {
        let data = try await requestData(
            baseURL: baseURL,
            apiToken: apiToken,
            path: "/api/v1/accounts/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)"
        )
        let box = try JSONDecoder().decode(CheckinAccountDetailBox.self, from: data)
        return box.account
    }

    func updateAccount(
        baseURL: String,
        apiToken: String,
        id: String,
        body: CheckinAccountUpdateBody
    ) async throws -> CheckinAccountDetail {
        let payload = try JSONEncoder().encode(body)
        let data = try await requestData(
            baseURL: baseURL,
            apiToken: apiToken,
            path: "/api/v1/accounts/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)",
            method: "PUT",
            body: payload
        )
        let box = try JSONDecoder().decode(CheckinAccountDetailBox.self, from: data)
        return box.account
    }

    func deleteAccount(baseURL: String, apiToken: String, id: String) async throws {
        _ = try await requestData(
            baseURL: baseURL,
            apiToken: apiToken,
            path: "/api/v1/accounts/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)",
            method: "DELETE"
        )
    }

    // MARK: - Telegram bots

    func deleteTelegramBot(baseURL: String, apiToken: String, botUsername: String) async throws {
        let user = botUsername.replacingOccurrences(of: "@", with: "")
        _ = try await requestData(
            baseURL: baseURL,
            apiToken: apiToken,
            path: "/api/v1/telegram/bots/\(user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user)",
            method: "DELETE"
        )
    }

    func updateTelegramBot(
        baseURL: String,
        apiToken: String,
        botUsername: String,
        body: CheckinTelegramBotUpdateBody
    ) async throws {
        let user = botUsername.replacingOccurrences(of: "@", with: "")
        let payload = try JSONEncoder().encode(body)
        _ = try await requestData(
            baseURL: baseURL,
            apiToken: apiToken,
            path: "/api/v1/telegram/bots/\(user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user)",
            method: "PUT",
            body: payload
        )
    }

    func deleteTelegramPhone(baseURL: String, apiToken: String, phone: String) async throws {
        let encoded = phone.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? phone
        _ = try await requestData(
            baseURL: baseURL,
            apiToken: apiToken,
            path: "/api/v1/telegram/phones/\(encoded)",
            method: "DELETE"
        )
    }
}
