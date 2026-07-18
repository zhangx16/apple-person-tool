import Foundation

/// Snapshot of CF credentials for actor-isolated API calls.
struct CFCredentials: Sendable {
    var apiToken: String
    var email: String
    var accountId: String

    init(apiToken: String, email: String = "", accountId: String = "") {
        self.apiToken = apiToken
        self.email = email
        self.accountId = accountId
    }

    @MainActor
    init(settings: AppSettings) {
        apiToken = settings.cloudflareAPIToken
        email = settings.cloudflareEmail
        accountId = settings.cloudflareAccountId
    }
}

/// Cloudflare REST + GraphQL client (MVP subset of CFPanel `util/api.ts`).
actor CloudflareService {
    static let shared = CloudflareService()
    private let client = NetworkClient.shared
    private let baseURL = "https://api.cloudflare.com"

    // MARK: - Auth

    private func authHeaders(email: String, token: String) -> [String: String] {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        var h = ["Content-Type": "application/json", "Accept": "application/json"]
        if e.isEmpty {
            h["Authorization"] = "Bearer \(t)"
        } else {
            h["X-Auth-Email"] = e
            h["X-Auth-Key"] = t
        }
        return h
    }

    private func headers(_ cred: CFCredentials) throws -> [String: String] {
        let token = cred.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw NetworkError.message("请先配置 Cloudflare API Token") }
        return authHeaders(email: cred.email, token: token)
    }

    // MARK: - Envelope

    private struct CFEnvelope<T: Decodable>: Decodable {
        let success: Bool
        let errors: [CFErrorItem]?
        let result: T?
        let result_info: CFResultInfo?
    }

    private struct CFErrorItem: Decodable {
        let code: Int?
        let message: String?
    }

    private struct CFResultInfo: Decodable {
        let page: Int?
        let per_page: Int?
        let total_pages: Int?
        let total_count: Int?
    }

    private struct EmptyResult: Decodable {}

    private func decodeEnvelope<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let env = try JSONDecoder().decode(CFEnvelope<T>.self, from: data)
        if !env.success {
            let msg = env.errors?.compactMap(\.message).joined(separator: "; ")
            throw NetworkError.message(msg?.isEmpty == false ? msg! : "Cloudflare 请求失败")
        }
        guard let result = env.result else {
            throw NetworkError.message("Cloudflare 返回空结果")
        }
        return result
    }

    private func request(
        cred: CFCredentials,
        path: String,
        method: String = "GET",
        body: Data? = nil,
        query: [URLQueryItem] = []
    ) async throws -> Data {
        let (data, http) = try await client.data(
            base: baseURL,
            path: path,
            method: method,
            headers: try headers(cred),
            body: body,
            query: query
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            if let env = try? JSONDecoder().decode(CFEnvelope<EmptyResult>.self, from: data),
               let msg = env.errors?.compactMap(\.message).joined(separator: "; "),
               !msg.isEmpty {
                throw NetworkError.message(msg)
            }
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        return data
    }

    // MARK: - Verify / Accounts

    func verifyToken(cred: CFCredentials) async throws -> CFTokenVerify {
        let email = cred.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty {
            let data = try await request(cred: cred, path: "/client/v4/user/tokens/verify")
            struct R: Decodable {
                let id: String?
                let status: String?
            }
            let r = try decodeEnvelope(data, as: R.self)
            return CFTokenVerify(status: r.status ?? "active", id: r.id)
        }
        _ = try await listZones(cred: cred, page: 1, perPage: 1)
        return CFTokenVerify(status: "active", id: nil)
    }

    func listAccounts(cred: CFCredentials) async throws -> [CFAccountOption] {
        var page = 1
        var totalPages = 1
        var all: [CFAccountOption] = []
        while page <= totalPages {
            let data = try await request(
                cred: cred,
                path: "/client/v4/accounts",
                query: [
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "per_page", value: "50")
                ]
            )
            struct Acc: Decodable {
                let id: String
                let name: String?
            }
            let env = try JSONDecoder().decode(CFEnvelope<[Acc]>.self, from: data)
            guard env.success, let result = env.result else {
                let msg = env.errors?.compactMap(\.message).joined(separator: "; ")
                throw NetworkError.message(msg ?? "无法列出账户")
            }
            all.append(contentsOf: result.map { CFAccountOption(id: $0.id, name: $0.name ?? $0.id) })
            totalPages = env.result_info?.total_pages ?? 1
            if result.count < 50 { break }
            page += 1
        }
        return all
    }

    // MARK: - Zones

    func listZones(cred: CFCredentials, page: Int = 1, perPage: Int = 50) async throws -> [CFZone] {
        var page = page
        var totalPages = 1
        var zones: [CFZone] = []
        while page <= totalPages {
            let data = try await request(
                cred: cred,
                path: "/client/v4/zones",
                query: [
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "per_page", value: "\(perPage)")
                ]
            )
            struct Z: Decodable {
                let id: String
                let name: String
                let status: String?
                let paused: Bool?
                let name_servers: [String]?
                let plan: Plan?
                struct Plan: Decodable { let name: String? }
            }
            let env = try JSONDecoder().decode(CFEnvelope<[Z]>.self, from: data)
            guard env.success, let result = env.result else {
                let msg = env.errors?.compactMap(\.message).joined(separator: "; ")
                throw NetworkError.message(msg ?? "无法获取域名列表")
            }
            zones.append(contentsOf: result.map {
                CFZone(
                    id: $0.id,
                    name: $0.name,
                    status: $0.status ?? "unknown",
                    paused: $0.paused ?? false,
                    planName: $0.plan?.name,
                    nameServers: $0.name_servers ?? []
                )
            })
            totalPages = env.result_info?.total_pages ?? 1
            if result.count < perPage { break }
            page += 1
        }
        return zones.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - DNS

    func listDNSRecords(cred: CFCredentials, zoneId: String) async throws -> [CFDnsRecord] {
        var page = 1
        var totalPages = 1
        var records: [CFDnsRecord] = []
        while page <= totalPages {
            let data = try await request(
                cred: cred,
                path: "/client/v4/zones/\(zoneId)/dns_records",
                query: [
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "per_page", value: "100")
                ]
            )
            struct R: Decodable {
                let id: String
                let type: String
                let name: String
                let content: String
                let ttl: Int?
                let proxied: Bool?
                let priority: Int?
            }
            let env = try JSONDecoder().decode(CFEnvelope<[R]>.self, from: data)
            guard env.success, let result = env.result else {
                let msg = env.errors?.compactMap(\.message).joined(separator: "; ")
                throw NetworkError.message(msg ?? "无法获取 DNS 记录")
            }
            records.append(contentsOf: result.map {
                CFDnsRecord(
                    id: $0.id,
                    type: $0.type,
                    name: $0.name,
                    content: $0.content,
                    ttl: $0.ttl ?? 1,
                    proxied: $0.proxied ?? false,
                    priority: $0.priority
                )
            })
            totalPages = env.result_info?.total_pages ?? 1
            if result.count < 100 { break }
            page += 1
        }
        return records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func createDNSRecord(cred: CFCredentials, zoneId: String, input: CFDnsRecordInput) async throws -> CFDnsRecord {
        var body: [String: Any] = [
            "type": input.type,
            "name": input.name,
            "content": input.content,
            "ttl": input.ttl,
            "proxied": input.proxied
        ]
        if let p = input.priority { body["priority"] = p }
        let data = try await request(
            cred: cred,
            path: "/client/v4/zones/\(zoneId)/dns_records",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return try parseDNSRecord(data)
    }

    func updateDNSRecord(
        cred: CFCredentials,
        zoneId: String,
        recordId: String,
        input: CFDnsRecordInput
    ) async throws -> CFDnsRecord {
        var body: [String: Any] = [
            "type": input.type,
            "name": input.name,
            "content": input.content,
            "ttl": input.ttl,
            "proxied": input.proxied
        ]
        if let p = input.priority { body["priority"] = p }
        let data = try await request(
            cred: cred,
            path: "/client/v4/zones/\(zoneId)/dns_records/\(recordId)",
            method: "PUT",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return try parseDNSRecord(data)
    }

    func deleteDNSRecord(cred: CFCredentials, zoneId: String, recordId: String) async throws {
        _ = try await request(
            cred: cred,
            path: "/client/v4/zones/\(zoneId)/dns_records/\(recordId)",
            method: "DELETE"
        )
    }

    private func parseDNSRecord(_ data: Data) throws -> CFDnsRecord {
        struct R: Decodable {
            let id: String
            let type: String
            let name: String
            let content: String
            let ttl: Int?
            let proxied: Bool?
            let priority: Int?
        }
        let r = try decodeEnvelope(data, as: R.self)
        return CFDnsRecord(
            id: r.id,
            type: r.type,
            name: r.name,
            content: r.content,
            ttl: r.ttl ?? 1,
            proxied: r.proxied ?? false,
            priority: r.priority
        )
    }

    // MARK: - Cache

    func purgeEverything(cred: CFCredentials, zoneId: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["purge_everything": true])
        _ = try await request(
            cred: cred,
            path: "/client/v4/zones/\(zoneId)/purge_cache",
            method: "POST",
            body: body
        )
    }

    // MARK: - Usage

    func fetchUsage(cred: CFCredentials) async throws -> CFUsageSnapshot {
        let accountId = cred.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountId.isEmpty else {
            throw NetworkError.message("请先填写 Cloudflare Account ID（可在设置中拉取账户列表）")
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let start = cal.startOfDay(for: now)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let query = """
        query getBillingMetrics($accountId: String!, $filter: AccountWorkersInvocationsAdaptiveFilter_InputObject) {
          viewer {
            accounts(filter: {accountTag: $accountId}) {
              pagesFunctionsInvocationsAdaptiveGroups(limit: 1000, filter: $filter) {
                sum { requests }
              }
              workersInvocationsAdaptive(limit: 10000, filter: $filter) {
                sum { requests }
              }
            }
          }
        }
        """
        let variables: [String: Any] = [
            "accountId": accountId,
            "filter": [
                "datetime_geq": formatter.string(from: start),
                "datetime_leq": formatter.string(from: now)
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables
        ])
        let data = try await request(
            cred: cred,
            path: "/client/v4/graphql",
            method: "POST",
            body: body
        )

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("用量响应无效")
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let msg = errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
            throw NetworkError.message(msg.isEmpty ? "GraphQL 查询失败" : msg)
        }

        let accounts = (((root["data"] as? [String: Any])?["viewer"] as? [String: Any])?["accounts"] as? [[String: Any]]) ?? []
        let account = accounts.first ?? [:]
        let pagesGroups = account["pagesFunctionsInvocationsAdaptiveGroups"] as? [[String: Any]] ?? []
        let workersGroups = account["workersInvocationsAdaptive"] as? [[String: Any]] ?? []

        func sumRequests(_ groups: [[String: Any]]) -> Int {
            groups.reduce(0) { partial, item in
                let sum = item["sum"] as? [String: Any]
                let n = sum?["requests"] as? Int ?? Int(sum?["requests"] as? Double ?? 0)
                return partial + n
            }
        }

        let pages = sumRequests(pagesGroups)
        let workers = sumRequests(workersGroups)
        let limitInfo = await fetchWorkerLimit(cred: cred)

        return CFUsageSnapshot(
            workersRequests: workers,
            pagesRequests: pages,
            dailyLimit: limitInfo.limit,
            planName: limitInfo.planName
        )
    }

    private func fetchWorkerLimit(cred: CFCredentials) async -> (limit: Int, planName: String) {
        let accountId = cred.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountId.isEmpty else { return (100_000, "Workers Free") }
        do {
            let data = try await request(
                cred: cred,
                path: "/client/v4/accounts/\(accountId)/subscriptions"
            )
            struct Sub: Decodable {
                let rate_plan: RatePlan?
                struct RatePlan: Decodable {
                    let id: String?
                    let public_name: String?
                }
            }
            let env = try JSONDecoder().decode(CFEnvelope<[Sub]>.self, from: data)
            let subs = env.result ?? []
            if let workersSub = subs.first(where: { ($0.rate_plan?.id ?? "").lowercased().contains("workers") }) {
                let planId = (workersSub.rate_plan?.id ?? "").lowercased()
                let name = workersSub.rate_plan?.public_name ?? ""
                if planId.contains("free") {
                    return (100_000, name.isEmpty ? "Workers Free" : name)
                }
                return (10_000_000, name.isEmpty ? "Workers Paid" : name)
            }
        } catch {}
        return (100_000, "Workers Free")
    }
}
