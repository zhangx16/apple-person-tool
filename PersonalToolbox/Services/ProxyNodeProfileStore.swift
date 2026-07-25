import Foundation

/// Snapshot of a proxy / node probe (IP + media + latency notes).
struct ProxyNodeProfile: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var egressIP: String
    var riskValue: Int
    var vpnStatus: String
    var pathStatus: String
    var mediaSummary: String
    var latencyMs: Int?
    var notes: String
    var createdAt: Date

    var subtitle: String {
        var parts: [String] = []
        if !egressIP.isEmpty { parts.append(egressIP) }
        parts.append("风险 \(riskValue)")
        if let latencyMs { parts.append("\(latencyMs)ms") }
        return parts.joined(separator: " · ")
    }
}

@MainActor
final class ProxyNodeProfileStore: ObservableObject {
    static let shared = ProxyNodeProfileStore()
    private let fileName = "proxyNodeProfiles.json"

    @Published private(set) var items: [ProxyNodeProfile] = []

    private init() {
        items = LocalJSONStore.load([ProxyNodeProfile].self, from: fileName, fallback: [])
        items.sort { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        LocalJSONStore.save(items, to: fileName)
    }

    func upsert(_ item: ProxyNodeProfile) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.insert(item, at: 0)
        }
        items.sort { $0.createdAt > $1.createdAt }
        persist()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    /// Run IP check (+ optional media) and rough latency to a host, then save.
    func probeAndSave(
        name: String,
        includeMedia: Bool,
        latencyHost: String?
    ) async -> (ProxyNodeProfile?, String?) {
        let (result, err) = await IPCheckService.shared.check(targetIP: nil, includeMedia: includeMedia)
        guard let result, let geo = result.primary else {
            return (nil, err ?? "无法探测出口")
        }

        var latency: Int?
        if let host = latencyHost?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            latency = await Self.measureLatency(host: host)
        }

        let mediaOK = result.mediaRows.filter { $0.status == "yes" }.map(\.name)
        let mediaNo = result.mediaRows.filter { $0.status == "no" }.map(\.name)
        var mediaSummary = "未测流媒体"
        if includeMedia {
            mediaSummary = "可用 \(mediaOK.prefix(3).joined(separator: "/"))"
            if !mediaNo.isEmpty {
                mediaSummary += " · 不可用 \(mediaNo.prefix(2).joined(separator: "/"))"
            }
        }

        let profile = ProxyNodeProfile(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "节点 \(geo.query)"
                : name.trimmingCharacters(in: .whitespacesAndNewlines),
            egressIP: geo.query,
            riskValue: result.riskValue,
            vpnStatus: result.vpnStatus,
            pathStatus: result.pathStatus,
            mediaSummary: mediaSummary,
            latencyMs: latency,
            notes: "\(geo.country) \(geo.city) · \(result.isHomeBroadband) · \(result.isNative)",
            createdAt: Date()
        )
        upsert(profile)
        return (profile, nil)
    }

    private static func measureLatency(host: String) async -> Int? {
        var h = host
        if h.hasPrefix("https://") { h = String(h.dropFirst(8)) }
        if h.hasPrefix("http://") { h = String(h.dropFirst(7)) }
        h = h.split(separator: "/").first.map(String.init) ?? h
        guard let url = URL(string: "https://\(h)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 6
        let t0 = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            _ = resp
            return Int(Date().timeIntervalSince(t0) * 1000)
        } catch {
            // Fallback GET tiny
            do {
                var g = URLRequest(url: url)
                g.timeoutInterval = 6
                let t1 = Date()
                _ = try await URLSession.shared.data(for: g)
                return Int(Date().timeIntervalSince(t1) * 1000)
            } catch {
                return nil
            }
        }
    }
}
