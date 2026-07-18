import Foundation
import CryptoKit

struct ExpressTrackEvent: Identifiable, Hashable, Codable {
    var id: String { "\(time)-\(context)" }
    var time: String
    var context: String
    var location: String?
}

struct ExpressRecord: Identifiable, Codable, Hashable {
    var id: String
    var trackingNo: String
    var carrierCode: String
    var carrierName: String
    var note: String
    var createdAt: Date
    var lastStatus: String
    var state: String?
    var tracks: [ExpressTrackEvent]
    var updatedAt: Date?
}

/// Realtime tracking via 快递100 poll/query when customer+key configured.
@MainActor
final class ExpressService: ObservableObject {
    static let shared = ExpressService()
    private let fileName = "express_packages_v2.json"

    @Published private(set) var packages: [ExpressRecord] = []
    @Published var lastLookupMessage: String?
    @Published var isQuerying = false

    private let settings = AppSettings.shared

    private init() {
        packages = LocalJSONStore.load([ExpressRecord].self, from: fileName, fallback: [])
    }

    private func persist() {
        LocalJSONStore.save(packages, to: fileName)
    }

    var hasAPICredentials: Bool {
        !settings.kuaidi100Customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.kuaidi100Key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func add(trackingNo: String, carrierHint: String = "", note: String = "") {
        let no = trackingNo.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !no.isEmpty else { return }
        if packages.contains(where: { $0.trackingNo == no }) { return }
        let name = carrierHint.isEmpty ? Self.guessCarrierName(no) : carrierHint
        let code = Self.guessCarrierCode(no)
        let rec = ExpressRecord(
            id: UUID().uuidString,
            trackingNo: no,
            carrierCode: code,
            carrierName: name,
            note: note,
            createdAt: Date(),
            lastStatus: hasAPICredentials ? "已保存，点查询获取轨迹" : "已保存（请在设置填写快递100密钥后查询）",
            state: nil,
            tracks: [],
            updatedAt: nil
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
        isQuerying = true
        defer { isQuerying = false }

        var rec = packages[idx]
        do {
            if hasAPICredentials {
                // Auto-detect company if unknown
                if rec.carrierCode.isEmpty || rec.carrierCode == "unknown" {
                    if let auto = try await autoCom(num: rec.trackingNo) {
                        rec.carrierCode = auto.code
                        rec.carrierName = auto.name
                    }
                }
                let result = try await queryKuaidi100(com: rec.carrierCode, num: rec.trackingNo)
                rec.tracks = result.tracks
                rec.lastStatus = result.tracks.first?.context ?? result.message
                rec.state = result.state
                rec.updatedAt = Date()
                lastLookupMessage = "查询成功：\(rec.lastStatus)"
            } else {
                // Free lightweight: only improve carrier guess + web hint
                rec.lastStatus = "未配置快递100 API。可跳转网页查询，或在设置中填写 customer/key。"
                lastLookupMessage = rec.lastStatus
            }
            packages[idx] = rec
            persist()
        } catch {
            packages[idx].lastStatus = "查询失败：\(error.localizedDescription)"
            lastLookupMessage = packages[idx].lastStatus
            persist()
        }
    }

    // MARK: - 快递100

    private struct AutoCom {
        var code: String
        var name: String
    }

    private func autoCom(num: String) async throws -> AutoCom? {
        let key = settings.kuaidi100Key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: "https://www.kuaidi100.com/autonumber/auto") else { return nil }
        c.queryItems = [
            URLQueryItem(name: "num", value: num),
            URLQueryItem(name: "key", value: key)
        ]
        guard let url = c.url else { return nil }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        // Response is array: [{"comCode":"yuantong","name":"圆通速递",...}]
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first,
           let code = first["comCode"] as? String {
            let name = (first["name"] as? String) ?? code
            return AutoCom(code: code, name: name)
        }
        return nil
    }

    private struct QueryResult {
        var tracks: [ExpressTrackEvent]
        var state: String?
        var message: String
    }

    private func queryKuaidi100(com: String, num: String) async throws -> QueryResult {
        let customer = settings.kuaidi100Customer.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = settings.kuaidi100Key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customer.isEmpty, !key.isEmpty else {
            throw NetworkError.message("请在设置中填写快递100 customer 与 key")
        }
        let comCode = com.isEmpty || com == "unknown" ? "auto" : com
        let paramObj: [String: Any] = [
            "com": comCode,
            "num": num,
            "resultv2": "1",
            "show": "0",
            "order": "desc"
        ]
        let paramData = try JSONSerialization.data(withJSONObject: paramObj)
        let param = String(data: paramData, encoding: .utf8) ?? "{}"
        let sign = Self.md5Upper("\(param)\(key)\(customer)")

        var req = URLRequest(url: URL(string: "https://poll.kuaidi100.com/poll/query.do")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "customer=\(customer.urlQueryEncoded)",
            "sign=\(sign.urlQueryEncoded)",
            "param=\(param.urlQueryEncoded)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NetworkError.message("无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("返回解析失败")
        }
        // status "200" success
        let status = "\(root["status"] ?? root["returnCode"] ?? "")"
        let message = (root["message"] as? String) ?? ""
        if status != "200" && status != "0" {
            throw NetworkError.message(message.isEmpty ? "查询失败 (\(status))" : message)
        }
        let state = root["state"] as? String
        var tracks: [ExpressTrackEvent] = []
        if let dataObj = root["data"] as? [[String: Any]] {
            for row in dataObj {
                let time = (row["time"] as? String) ?? (row["ftime"] as? String) ?? ""
                let context = (row["context"] as? String) ?? (row["status"] as? String) ?? ""
                let location = row["location"] as? String
                if !context.isEmpty {
                    tracks.append(ExpressTrackEvent(time: time, context: context, location: location))
                }
            }
        }
        return QueryResult(tracks: tracks, state: state, message: message.isEmpty ? "ok" : message)
    }

    static func md5Upper(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    static func guessCarrierName(_ no: String) -> String {
        switch guessCarrierCode(no) {
        case "shunfeng": return "顺丰"
        case "yuantong": return "圆通"
        case "yunda": return "韵达"
        case "zhongtong": return "中通"
        case "shentong": return "申通"
        case "jtexpress": return "极兔"
        case "jd": return "京东"
        case "ems": return "EMS"
        default: return "自动识别"
        }
    }

    static func guessCarrierCode(_ no: String) -> String {
        let u = no.uppercased()
        if u.hasPrefix("SF") { return "shunfeng" }
        if u.hasPrefix("YT") { return "yuantong" }
        if u.hasPrefix("YD") { return "yunda" }
        if u.hasPrefix("ZT") || u.hasPrefix("ZTO") { return "zhongtong" }
        if u.hasPrefix("STO") { return "shentong" }
        if u.hasPrefix("JT") { return "jtexpress" }
        if u.hasPrefix("JD") { return "jd" }
        if u.hasPrefix("EMS") || (u.count == 13 && u.hasSuffix("CN")) { return "ems" }
        return "unknown"
    }

    static func kuaidi100URL(trackingNo: String) -> URL? {
        var c = URLComponents(string: "https://m.kuaidi100.com/result.jsp")
        c?.queryItems = [URLQueryItem(name: "nu", value: trackingNo)]
        return c?.url
    }
}

private extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
