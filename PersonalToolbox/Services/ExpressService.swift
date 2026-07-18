import Foundation

struct ExpressRecord: Identifiable, Codable, Hashable {
    var id: String
    var trackingNo: String
    var carrierHint: String
    var note: String
    var createdAt: Date
    var lastStatus: String
}

/// Local tracking notebook + heuristic status.
/// Full realtime carrier APIs usually need a commercial key; we store numbers and show guidance.
@MainActor
final class ExpressService: ObservableObject {
    static let shared = ExpressService()
    private let fileName = "express_packages.json"

    @Published private(set) var packages: [ExpressRecord] = []
    @Published var lastLookupMessage: String?

    private init() {
        packages = LocalJSONStore.load([ExpressRecord].self, from: fileName, fallback: [])
    }

    private func persist() {
        LocalJSONStore.save(packages, to: fileName)
    }

    func add(trackingNo: String, carrierHint: String = "", note: String = "") {
        let no = trackingNo.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !no.isEmpty else { return }
        if packages.contains(where: { $0.trackingNo == no }) { return }
        let carrier = carrierHint.isEmpty ? Self.guessCarrier(no) : carrierHint
        let rec = ExpressRecord(
            id: UUID().uuidString,
            trackingNo: no,
            carrierHint: carrier,
            note: note,
            createdAt: Date(),
            lastStatus: "已保存，待查询"
        )
        packages.insert(rec, at: 0)
        persist()
    }

    func delete(id: String) {
        packages.removeAll { $0.id == id }
        persist()
    }

    func lookup(_ id: String) async {
        guard let idx = packages.firstIndex(where: { $0.id == id }) else { return }
        let no = packages[idx].trackingNo
        // Try a public redirect page existence check is useless; provide deep-link friendly status.
        packages[idx].lastStatus = "请用 \(packages[idx].carrierHint.isEmpty ? "承运商" : packages[idx].carrierHint) App / 官网查询 \(no)"
        lastLookupMessage = packages[idx].lastStatus
        persist()

        // Optional: open kuaidi100 query URL is handled in UI via Safari
    }

    static func guessCarrier(_ no: String) -> String {
        let u = no.uppercased()
        if u.hasPrefix("SF") { return "顺丰" }
        if u.hasPrefix("YT") { return "圆通" }
        if u.hasPrefix("YD") { return "韵达" }
        if u.hasPrefix("ZT") || u.hasPrefix("ZTO") { return "中通" }
        if u.hasPrefix("STO") { return "申通" }
        if u.hasPrefix("JT") { return "极兔" }
        if u.hasPrefix("JD") { return "京东" }
        if u.hasPrefix("EMS") || (u.count == 13 && u.hasSuffix("CN")) { return "EMS" }
        return "未知承运商"
    }

    static func kuaidi100URL(trackingNo: String) -> URL? {
        var c = URLComponents(string: "https://m.kuaidi100.com/result.jsp")
        c?.queryItems = [URLQueryItem(name: "nu", value: trackingNo)]
        return c?.url
    }
}
