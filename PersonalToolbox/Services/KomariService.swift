import Foundation

/// Komari public monitoring API — aligned with [komari-monitor/komari](https://github.com/komari-monitor/komari).
/// Public endpoints (no auth): `/api/nodes`, `/api/recent/:uuid`, `/api/records/*`, `/api/version`, `/api/public`.
actor KomariService {
    static let shared = KomariService()
    private let client = NetworkClient.shared

    func version(baseURL: String) async throws -> KomariVersion {
        try await get(baseURL: baseURL, path: "/api/version")
    }

    func publicSettings(baseURL: String) async throws -> KomariPublicSettings {
        try await get(baseURL: baseURL, path: "/api/public")
    }

    func listNodes(baseURL: String) async throws -> [KomariNode] {
        let nodes: [KomariNode] = try await get(baseURL: baseURL, path: "/api/nodes")
        return nodes.filter { !($0.hidden ?? false) }
    }

    func recent(baseURL: String, uuid: String) async throws -> [KomariRecentSample] {
        try await get(baseURL: baseURL, path: "/api/recent/\(uuid)")
    }

    func loadRecords(
        baseURL: String,
        uuid: String,
        hours: Int = 6
    ) async throws -> KomariLoadRecordsBox {
        try await get(
            baseURL: baseURL,
            path: "/api/records/load",
            query: [
                .init(name: "uuid", value: uuid),
                .init(name: "hours", value: String(hours))
            ]
        )
    }

    func pingRecords(
        baseURL: String,
        uuid: String,
        hours: Int = 6
    ) async throws -> KomariPingRecordsBox {
        try await get(
            baseURL: baseURL,
            path: "/api/records/ping",
            query: [
                .init(name: "uuid", value: uuid),
                .init(name: "hours", value: String(hours))
            ]
        )
    }

    func pingTasks(baseURL: String) async throws -> [KomariPingTask] {
        try await get(baseURL: baseURL, path: "/api/task/ping")
    }

    /// Merge node inventory with latest sample per uuid (batched concurrent fetches).
    func dashboard(baseURL: String) async throws -> [KomariNodeRow] {
        let nodes = try await listNodes(baseURL: baseURL)
        guard !nodes.isEmpty else { return [] }

        var samplesByUUID: [String: KomariRecentSample] = [:]
        samplesByUUID.reserveCapacity(nodes.count)

        // Bounded concurrency so large fleets don't open dozens of sockets at once.
        let chunkSize = 8
        var start = 0
        while start < nodes.count {
            let end = min(start + chunkSize, nodes.count)
            let slice = Array(nodes[start..<end])
            await withTaskGroup(of: (String, KomariRecentSample?).self) { group in
                for node in slice {
                    group.addTask {
                        let samples = try? await self.recent(baseURL: baseURL, uuid: node.uuid)
                        return (node.uuid, samples?.first)
                    }
                }
                for await (uuid, sample) in group {
                    if let sample {
                        samplesByUUID[uuid] = sample
                    }
                }
            }
            start = end
        }

        return nodes.map { node in
            KomariNodeRow(node: node, recent: samplesByUUID[node.uuid])
        }
        .sorted { ($0.node.weight ?? 0) < ($1.node.weight ?? 0) }
    }

    func probe(baseURL: String) async throws -> String {
        async let nodes = listNodes(baseURL: baseURL)
        async let ver = version(baseURL: baseURL)
        let n = try await nodes
        let v = try? await ver
        let versionText = v?.version.map { " v\($0)" } ?? ""
        return "节点 \(n.count) 台\(versionText)"
    }

    // MARK: - HTTP

    private func get<T: Decodable>(
        baseURL: String,
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let (data, http) = try await client.data(
            base: baseURL,
            path: path,
            headers: ["Accept": "application/json"],
            query: query
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        let env = try JSONDecoder().decode(KomariEnvelope<T>.self, from: data)
        if let status = env.status, status != "success", env.data == nil {
            throw NetworkError.message(env.message ?? "Komari 请求失败")
        }
        guard let payload = env.data else {
            throw NetworkError.message(env.message ?? "Komari 无数据")
        }
        return payload
    }
}
