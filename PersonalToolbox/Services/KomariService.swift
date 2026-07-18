import Foundation

/// Komari (https://komari.996616.xyz) public monitoring API — no auth for node list / recent metrics.
actor KomariService {
    static let shared = KomariService()
    private let client = NetworkClient.shared

    func listNodes(baseURL: String) async throws -> [KomariNode] {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/nodes",
            headers: ["Accept": "application/json"]
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        let env = try JSONDecoder().decode(KomariEnvelope<[KomariNode]>.self, from: data)
        return (env.data ?? []).filter { !($0.hidden ?? false) }
    }

    func recent(baseURL: String, uuid: String) async throws -> [KomariRecentSample] {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/api/recent/\(uuid)",
            headers: ["Accept": "application/json"]
        )
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        let env = try JSONDecoder().decode(KomariEnvelope<[KomariRecentSample]>.self, from: data)
        return env.data ?? []
    }

    /// Merge node inventory with latest sample per uuid.
    func dashboard(baseURL: String) async throws -> [KomariNodeRow] {
        let nodes = try await listNodes(baseURL: baseURL)
        var rows: [KomariNodeRow] = []
        rows.reserveCapacity(nodes.count)
        // Fetch recent in parallel-ish batches to avoid hammering
        for node in nodes {
            let samples = try? await recent(baseURL: baseURL, uuid: node.uuid)
            rows.append(KomariNodeRow(node: node, recent: samples?.first))
        }
        return rows.sorted { ($0.node.weight ?? 0) < ($1.node.weight ?? 0) }
    }

    func probe(baseURL: String) async throws -> String {
        let nodes = try await listNodes(baseURL: baseURL)
        return "在线节点 \(nodes.count) 台"
    }
}
