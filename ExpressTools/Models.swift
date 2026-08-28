import Foundation

struct TrackingEvent: Codable, Hashable, Identifiable {
    var id: String { "\(time)|\(description)" }
    let time: String
    let description: String
    let location: String?
}

struct Parcel: Codable, Hashable, Identifiable {
    let id: UUID
    var number: String
    var carrierCode: String
    var carrierName: String
    var alias: String
    var phoneTail: String
    var state: String?
    var summary: String
    var events: [TrackingEvent]
    var createdAt: Date
    var updatedAt: Date?
    var isWatching: Bool

    var title: String { alias.isEmpty ? carrierName : alias }
    var bucket: ParcelBucket {
        switch state {
        case "3": .completed
        case "2", "4", "6", "13", "14": .abnormal
        default: .active
        }
    }
    var statusText: String { CarrierCatalog.stateName(state) ?? (events.isEmpty ? "等待查询" : "运输中") }
    var progress: Double {
        switch state { case "1": 0.18; case "0", "7": 0.55; case "5": 0.88; case "3": 1; default: events.isEmpty ? 0.05 : 0.35 }
    }
    var pickupCode: String? {
        let text = events.map(\.description).joined(separator: " ")
        guard let range = text.range(of: #"(?:取件码|提货码|凭码)[：:\s]*([A-Z0-9-]{3,})"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[range]).components(separatedBy: CharacterSet(charactersIn: "：: ")).last(where: { !$0.isEmpty })
    }
    var estimatedDate: Date? {
        let text = events.map(\.description).joined(separator: " ")
        guard let range = text.range(of: #"预计[^。；;]{0,16}?(\d{1,2})月(\d{1,2})日"#, options: .regularExpression) else { return state == "5" ? Date() : nil }
        let values = String(text[range]).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard values.count >= 2 else { return nil }
        var components = Calendar.current.dateComponents([.year], from: Date())
        components.month = values[values.count - 2]; components.day = values[values.count - 1]
        return Calendar.current.date(from: components)
    }
}

enum ParcelBucket: String, CaseIterable, Identifiable {
    case active = "在途", completed = "已完成", abnormal = "异常"
    var id: String { rawValue }
    var icon: String { self == .active ? "box.truck.fill" : self == .completed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
}

enum CarrierCatalog {
    static func guess(_ number: String) -> (String, String) {
        let value = number.uppercased()
        let pair: (String, String)
        if value.hasPrefix("SF") { pair = ("shunfeng", "顺丰速运") }
        else if value.hasPrefix("YT") { pair = ("yuantong", "圆通速递") }
        else if value.hasPrefix("YD") { pair = ("yunda", "韵达快递") }
        else if value.hasPrefix("ZT") { pair = ("zhongtong", "中通快递") }
        else if value.hasPrefix("JT") { pair = ("jtexpress", "极兔速递") }
        else if value.hasPrefix("JD") { pair = ("jd", "京东快递") }
        else if value.hasPrefix("EMS") || (value.count == 13 && value.hasSuffix("CN")) { pair = ("ems", "EMS") }
        else { pair = ("unknown", "自动识别") }
        return pair
    }
    static func name(_ code: String) -> String { ["shunfeng":"顺丰速运", "yuantong":"圆通速递", "yunda":"韵达快递", "zhongtong":"中通快递", "shentong":"申通快递", "jtexpress":"极兔速递", "jd":"京东快递", "ems":"EMS", "youzhengguonei":"邮政包裹"][code] ?? code }
    static func stateName(_ state: String?) -> String? { ["0":"在途", "1":"揽收", "2":"疑难", "3":"已签收", "4":"退签", "5":"派件", "6":"退回", "7":"转投", "10":"待清关", "11":"清关中", "12":"已清关", "13":"清关异常", "14":"拒签"][state ?? ""] }
}
