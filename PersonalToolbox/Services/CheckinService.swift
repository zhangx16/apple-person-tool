import Foundation

/// Client for glados-checkin-web mobile API (`/api/v1/*`).
actor CheckinService {
    static let shared = CheckinService()
    private let client = NetworkClient.shared

    private func headers(apiToken: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiToken)",
            "Accept": "application/json"
        ]
    }

    /// Lightweight auth + reachability probe.
    func health(baseURL: String, apiToken: String) async throws -> CheckinHealth {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/v1/health",
            headers: headers(apiToken: apiToken)
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        do {
            return try JSONDecoder().decode(CheckinHealth.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    /// Aggregated check-in status for all website accounts + Telegram bots.
    func summary(baseURL: String, apiToken: String) async throws -> CheckinSummary {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/v1/summary",
            headers: headers(apiToken: apiToken)
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        do {
            return try JSONDecoder().decode(CheckinSummary.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }
}
