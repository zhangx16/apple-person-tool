import Foundation

struct CertWatchItem: Identifiable, Codable, Hashable {
    var id: String
    var host: String
    var port: Int
    var note: String
    /// Manual or probed expiry (user can edit).
    var notAfter: Date?
    var lastChecked: Date?
    var lastOK: Bool?
    var error: String?

    var daysLeft: Int? {
        guard let notAfter else { return nil }
        return Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: notAfter)
        ).day
    }
}

@MainActor
final class CertExpiryStore: ObservableObject {
    static let shared = CertExpiryStore()
    private let fileName = "cert_watchlist.json"

    @Published private(set) var items: [CertWatchItem] = []
    @Published private(set) var isChecking = false

    private init() {
        items = LocalJSONStore.load([CertWatchItem].self, from: fileName, fallback: [])
    }

    private func persist() {
        LocalJSONStore.save(items, to: fileName)
    }

    func add(host: String, port: Int = 443, note: String = "", notAfter: Date? = nil) {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if let slash = h.firstIndex(of: "/") {
            h = String(h[..<slash])
        }
        guard !h.isEmpty else { return }
        if items.contains(where: { $0.host.caseInsensitiveCompare(h) == .orderedSame && $0.port == port }) {
            return
        }
        items.append(
            CertWatchItem(
                id: UUID().uuidString,
                host: h,
                port: port,
                note: note,
                notAfter: notAfter,
                lastChecked: nil,
                lastOK: nil,
                error: nil
            )
        )
        persist()
    }

    func update(_ item: CertWatchItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        persist()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    /// HTTPS reachability probe (does not always parse notAfter on all iOS versions).
    func refreshAll() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        for i in items.indices {
            let host = items[i].host
            let port = items[i].port
            let ok = await Self.probeHTTPS(host: host, port: port)
            items[i].lastChecked = Date()
            items[i].lastOK = ok.ok
            items[i].error = ok.error
        }
        persist()
    }

    var expiringSoon: [CertWatchItem] {
        items.filter { item in
            if let d = item.daysLeft, d <= 30 { return true }
            return false
        }
    }

    nonisolated private static func probeHTTPS(host: String, port: Int) async -> (ok: Bool, error: String?) {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        if port != 443 { comps.port = port }
        comps.path = "/"
        guard let url = comps.url else { return (false, "无效主机") }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 12
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                return (true, "HTTP \(http.statusCode)")
            }
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
