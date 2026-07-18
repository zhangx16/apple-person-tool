import Foundation
import CryptoKit

struct ExpressTrackEvent: Identifiable, Hashable, Codable {
    var id: String { "\(time)-\(context)" }
    var time: String
    var context: String
    var location: String?
    var status: String?
}

struct ExpressRecord: Identifiable, Codable, Hashable {
    var id: String
    var trackingNo: String
    var carrierCode: String
    var carrierName: String
    var note: String
    /// 顺丰等可能需要手机号后四位
    var phoneTail: String
    var createdAt: Date
    var lastStatus: String
    var state: String?
    var tracks: [ExpressTrackEvent]
    var updatedAt: Date?
}

/// 快递100 实时查询（官方 poll/query 协议，对齐 Python/Java 示例）。
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

    func add(trackingNo: String, carrierHint: String = "", note: String = "", phoneTail: String = "") {
        let no = trackingNo.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !no.isEmpty else { return }
        if packages.contains(where: { $0.trackingNo == no }) { return }
        let code = Self.guessCarrierCode(no)
        let name = carrierHint.isEmpty ? Self.guessCarrierName(no) : carrierHint
        let rec = ExpressRecord(
            id: UUID().uuidString,
            trackingNo: no,
            carrierCode: code,
            carrierName: name,
            note: note,
            phoneTail: phoneTail.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            lastStatus: hasAPICredentials ? "已保存，查询中…" : "已保存（请配置快递100密钥）",
            state: nil,
            tracks: [],
            updatedAt: nil
        )
        packages.insert(rec, at: 0)
        persist()
    }

    func updatePhoneTail(id: String, phoneTail: String) {
        guard let i = packages.firstIndex(where: { $0.id == id }) else { return }
        packages[i].phoneTail = phoneTail.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard hasAPICredentials else {
            rec.lastStatus = "未配置快递100 API（设置 → 快递100）"
            packages[idx] = rec
            lastLookupMessage = rec.lastStatus
            persist()
            return
        }

        do {
            // 1) Try official auto company (may fail if auto key product expired)
            if rec.carrierCode.isEmpty || rec.carrierCode == "unknown" {
                if let auto = try? await autoCom(num: rec.trackingNo) {
                    rec.carrierCode = auto.code
                    rec.carrierName = auto.name
                }
            }

            // 2) Query with primary code, then fallback candidates
            var lastError: Error?
            let candidates = Self.queryCandidates(primary: rec.carrierCode, number: rec.trackingNo)
            var success = false
            for com in candidates {
                do {
                    let result = try await queryKuaidi100(
                        com: com,
                        num: rec.trackingNo,
                        phone: rec.phoneTail
                    )
                    rec.carrierCode = com
                    if rec.carrierName.isEmpty || rec.carrierName == "自动识别" {
                        rec.carrierName = Self.nameForCode(com)
                    }
                    rec.tracks = result.tracks
                    rec.lastStatus = result.tracks.first?.context ?? result.message
                    rec.state = result.stateLabel
                    rec.updatedAt = Date()
                    lastLookupMessage = "查询成功（\(rec.carrierName)）"
                    success = true
                    break
                } catch {
                    lastError = error
                    continue
                }
            }
            if !success {
                throw lastError ?? NetworkError.message("查询失败")
            }
            packages[idx] = rec
            persist()
        } catch {
            packages[idx].lastStatus = "查询失败：\(error.localizedDescription)"
            lastLookupMessage = packages[idx].lastStatus
            persist()
        }
    }

    // MARK: - Official API (matches kuaidi100 Python/Java samples)

    private struct AutoCom {
        var code: String
        var name: String
    }

    /// 智能单号识别（需 key；若 key 仅开通实时查询未开通识别，会 601，忽略即可）。
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
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first,
           let code = first["comCode"] as? String, !code.isEmpty {
            let name = (first["name"] as? String) ?? code
            return AutoCom(code: code, name: name)
        }
        // { returnCode: 601, message: key过期 }
        return nil
    }

    private struct QueryResult {
        var tracks: [ExpressTrackEvent]
        var state: String?
        var stateLabel: String?
        var message: String
    }

    private func queryKuaidi100(com: String, num: String, phone: String) async throws -> QueryResult {
        let customer = settings.kuaidi100Customer.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = settings.kuaidi100Key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customer.isEmpty, !key.isEmpty else {
            throw NetworkError.message("请在设置中填写快递100 customer 与 key")
        }

        // 官方要求：param 为紧凑 JSON 字符串，sign = MD5(param + key + customer).upper()
        // 字段顺序与 Python json.dumps(separators=(',',':')) 一致（按插入顺序）
        var ordered: [(String, String)] = [
            ("com", com),
            ("num", num),
            ("phone", phone),
            ("resultv2", "1"),
            ("show", "0"),
            ("order", "desc")
        ]
        let param = Self.compactJSONObject(ordered)
        let sign = Self.md5Upper(param + key + customer)

        var req = URLRequest(url: URL(string: "https://poll.kuaidi100.com/poll/query.do")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XIN's Tool iOS", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        req.httpBody = Self.formBody([
            ("customer", customer),
            ("sign", sign),
            ("param", param)
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NetworkError.message("无响应")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("返回解析失败")
        }

        // status "200" 成功；returnCode 用于错误
        let status = "\(root["status"] ?? "")"
        let returnCode = "\(root["returnCode"] ?? "")"
        let message = (root["message"] as? String) ?? ""

        if status == "200" {
            let state = root["state"] as? String
            var tracks: [ExpressTrackEvent] = []
            if let rows = root["data"] as? [[String: Any]] {
                for row in rows {
                    let time = (row["time"] as? String) ?? (row["ftime"] as? String) ?? ""
                    let context = (row["context"] as? String) ?? ""
                    let location = row["location"] as? String ?? row["areaName"] as? String
                    let st = row["status"] as? String
                    if !context.isEmpty {
                        tracks.append(ExpressTrackEvent(time: time, context: context, location: location, status: st))
                    }
                }
            }
            let comName = (root["com"] as? String).map(Self.nameForCode) 
            return QueryResult(
                tracks: tracks,
                state: state,
                stateLabel: Self.stateLabel(state) ?? comName,
                message: message.isEmpty ? "ok" : message
            )
        }

        // 常见错误码中文化
        let code = returnCode.isEmpty ? status : returnCode
        let friendly: String
        switch code {
        case "408":
            friendly = "参数异常（顺丰请填写手机号后四位再查）"
        case "500":
            friendly = message.isEmpty ? "查询无结果" : message
        case "503":
            friendly = "签名验证失败，请检查 customer/key"
        case "601":
            friendly = "key 过期或未开通该接口权限"
        case "401":
            friendly = "不支持该快递公司编码"
        case "400":
            friendly = "找不到对应快递公司"
        default:
            friendly = message.isEmpty ? "查询失败 (\(code))" : "\(message) (\(code))"
        }
        throw NetworkError.message(friendly)
    }

    /// 紧凑 JSON：{"k":"v",...} 无空格，键按给定顺序。
    private static func compactJSONObject(_ pairs: [(String, String)]) -> String {
        let escaped = pairs.map { key, value -> String in
            let k = escapeJSONString(key)
            let v = escapeJSONString(value)
            return "\"\(k)\":\"\(v)\""
        }
        return "{\(escaped.joined(separator: ","))}"
    }

    private static func escapeJSONString(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        return out
    }

    private static func formBody(_ pairs: [(String, String)]) -> Data {
        let encoded = pairs.map { k, v in
            "\(formEncode(k))=\(formEncode(v))"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    private static func formEncode(_ s: String) -> String {
        // application/x-www-form-urlencoded
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._* ")
        let enc = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        return enc.replacingOccurrences(of: " ", with: "+")
    }

    static func md5Upper(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    static func queryCandidates(primary: String, number: String) -> [String] {
        var list: [String] = []
        if !primary.isEmpty, primary != "unknown" { list.append(primary) }
        let guess = guessCarrierCode(number)
        if guess != "unknown", !list.contains(guess) { list.append(guess) }
        // Common fallbacks
        for c in ["yuantong", "zhongtong", "shentong", "yunda", "jtexpress", "shunfeng", "jd", "ems", "youzhengguonei"] {
            if !list.contains(c) { list.append(c) }
        }
        return list
    }

    static func stateLabel(_ state: String?) -> String? {
        guard let state else { return nil }
        switch state {
        case "0": return "在途"
        case "1": return "揽收"
        case "2": return "疑难"
        case "3": return "已签收"
        case "4": return "退签"
        case "5": return "派件"
        case "6": return "退回"
        case "7": return "转投"
        case "10": return "待清关"
        case "11": return "清关中"
        case "12": return "已清关"
        case "13": return "清关异常"
        case "14": return "拒签"
        default: return state
        }
    }

    static func nameForCode(_ code: String) -> String {
        switch code {
        case "shunfeng": return "顺丰"
        case "yuantong": return "圆通"
        case "yunda": return "韵达"
        case "zhongtong": return "中通"
        case "shentong": return "申通"
        case "jtexpress": return "极兔"
        case "jd": return "京东"
        case "ems", "youzhengguonei": return "邮政/EMS"
        default: return code
        }
    }

    static func guessCarrierName(_ no: String) -> String {
        nameForCode(guessCarrierCode(no))
    }

    static func guessCarrierCode(_ no: String) -> String {
        let u = no.uppercased()
        if u.hasPrefix("SF") { return "shunfeng" }
        if u.hasPrefix("YT") { return "yuantong" }
        if u.hasPrefix("YD") { return "yunda" }
        if u.hasPrefix("ZT") || u.hasPrefix("ZTO") { return "zhongtong" }
        if u.hasPrefix("STO") || u.hasPrefix("77") { return "shentong" }
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
