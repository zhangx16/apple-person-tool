import Foundation
import CryptoKit

/// SublinkX API envelope often uses `code: "00000"` for success.
struct SublinkEnvelope<T: Decodable>: Decodable {
    let code: FlexibleCode?
    let msg: String?
    let message: String?
    let data: T?

    var isSuccess: Bool {
        switch code {
        case .string(let s): return s == "00000" || s == "0"
        case .int(let i): return i == 0
        case .none: return data != nil
        }
    }

    var errorText: String {
        msg ?? message ?? "请求失败"
    }
}

/// Envelope without typed data (write endpoints that only return code/msg).
struct SublinkStatusEnvelope: Decodable {
    let code: FlexibleCode?
    let msg: String?
    let message: String?

    var isSuccess: Bool {
        switch code {
        case .string(let s): return s == "00000" || s == "0"
        case .int(let i): return i == 0
        case .none: return false
        }
    }

    var errorText: String {
        msg ?? message ?? "请求失败"
    }
}

enum FlexibleCode: Decodable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            self = .int(i)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        throw DecodingError.typeMismatch(
            FlexibleCode.self,
            .init(codingPath: decoder.codingPath, debugDescription: "code must be string or int")
        )
    }
}

struct SublinkCaptcha: Decodable {
    var captchaBase64: String?
    var captchaId: String?
    var captchaKey: String?
    var uuid: String?
    var id: String?

    var imageDataURL: String? { captchaBase64 }
    var captchaToken: String? { captchaId ?? captchaKey ?? uuid ?? id }
}

struct SublinkLoginData: Decodable {
    var accessToken: String?
    var token: String?
    var refreshToken: String?

    var bearer: String? { accessToken ?? token }
}

struct SublinkGroupRef: Decodable, Hashable {
    var name: String?

    enum CodingKeys: String, CodingKey {
        case name, Name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .Name))
            ?? (try? c.decodeIfPresent(String.self, forKey: .name))
    }

    init(name: String?) {
        self.name = name
    }
}

struct SublinkNode: Decodable, Identifiable, Hashable {
    var id: Int { nodeId ?? stableFallback }
    var nodeId: Int?
    var name: String?
    var link: String?
    var groupNodes: [SublinkGroupRef]?

    var groupNames: [String] {
        (groupNodes ?? [])
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var groupCSV: String {
        groupNames.joined(separator: ",")
    }

    var displayName: String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "未命名节点" : n
    }

    private var stableFallback: Int {
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(link)
        return hasher.finalize()
    }

    enum CodingKeys: String, CodingKey {
        case name, link
        case nodeId = "ID"
        case Name, Link, id
        case groupNodes = "GroupNodes"
        case group_nodes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodeId = (try? c.decodeIfPresent(Int.self, forKey: .nodeId))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .id))
        name = (try? c.decodeIfPresent(String.self, forKey: .Name))
            ?? (try? c.decodeIfPresent(String.self, forKey: .name))
        link = (try? c.decodeIfPresent(String.self, forKey: .Link))
            ?? (try? c.decodeIfPresent(String.self, forKey: .link))
        groupNodes = (try? c.decodeIfPresent([SublinkGroupRef].self, forKey: .groupNodes))
            ?? (try? c.decodeIfPresent([SublinkGroupRef].self, forKey: .group_nodes))
    }

    init(nodeId: Int?, name: String?, link: String?, groupNodes: [SublinkGroupRef]? = nil) {
        self.nodeId = nodeId
        self.name = name
        self.link = link
        self.groupNodes = groupNodes
    }
}

struct SublinkSubLog: Decodable, Identifiable, Hashable {
    var id: String { "\(ip ?? "")-\(date ?? "")-\(addr ?? "")-\(count ?? 0)" }
    var ip: String?
    var count: Int?
    var addr: String?
    var date: String?

    enum CodingKeys: String, CodingKey {
        case ip = "IP"
        case count = "Count"
        case addr = "Addr"
        case date = "Date"
        case Ip, Address, address
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ip = (try? c.decodeIfPresent(String.self, forKey: .ip))
            ?? (try? c.decodeIfPresent(String.self, forKey: .Ip))
        count = try? c.decodeIfPresent(Int.self, forKey: .count)
        addr = (try? c.decodeIfPresent(String.self, forKey: .addr))
            ?? (try? c.decodeIfPresent(String.self, forKey: .Address))
            ?? (try? c.decodeIfPresent(String.self, forKey: .address))
        date = try? c.decodeIfPresent(String.self, forKey: .date)
    }
}

struct SublinkSub: Decodable, Identifiable, Hashable {
    var id: Int { subId ?? stableFallback }
    var subId: Int?
    var name: String?
    var config: String?
    var nodeOrder: String?
    var nodes: [SublinkNode]?
    var subLogs: [SublinkSubLog]?

    var displayName: String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "未命名订阅" : n
    }

    var nodeNames: [String] {
        if let nodes, !nodes.isEmpty {
            return nodes.compactMap { $0.name }.filter { !$0.isEmpty }
        }
        guard let nodeOrder, !nodeOrder.isEmpty else { return [] }
        return nodeOrder
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var parsedConfig: SublinkSubConfig {
        SublinkSubConfig.parse(config)
    }

    private var stableFallback: Int {
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(config)
        return hasher.finalize()
    }

    enum CodingKeys: String, CodingKey {
        case name, config
        case subId = "ID"
        case Name, Config, id
        case nodeOrder = "NodeOrder"
        case NodeOrder
        case nodes = "Nodes"
        case Nodes
        case subLogs = "SubLogs"
        case SubLogs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subId = (try? c.decodeIfPresent(Int.self, forKey: .subId))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .id))
        name = (try? c.decodeIfPresent(String.self, forKey: .Name))
            ?? (try? c.decodeIfPresent(String.self, forKey: .name))
        config = (try? c.decodeIfPresent(String.self, forKey: .Config))
            ?? (try? c.decodeIfPresent(String.self, forKey: .config))
        nodeOrder = (try? c.decodeIfPresent(String.self, forKey: .NodeOrder))
            ?? (try? c.decodeIfPresent(String.self, forKey: .nodeOrder))
        nodes = (try? c.decodeIfPresent([SublinkNode].self, forKey: .Nodes))
            ?? (try? c.decodeIfPresent([SublinkNode].self, forKey: .nodes))
        subLogs = (try? c.decodeIfPresent([SublinkSubLog].self, forKey: .SubLogs))
            ?? (try? c.decodeIfPresent([SublinkSubLog].self, forKey: .subLogs))
    }
}

/// Subscription `config` JSON stored by SublinkX web UI.
struct SublinkSubConfig: Codable, Equatable {
    var clash: String
    var surge: String
    var udp: Bool
    var cert: Bool

    static let `default` = SublinkSubConfig(
        clash: "./template/clash.yaml",
        surge: "./template/surge.conf",
        udp: false,
        cert: false
    )

    static func parse(_ raw: String?) -> SublinkSubConfig {
        guard let raw, let data = raw.data(using: .utf8),
              let obj = try? JSONDecoder().decode(SublinkSubConfig.self, from: data) else {
            return .default
        }
        return obj
    }

    func jsonString() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(self),
              let s = String(data: data, encoding: .utf8) else {
            return "{\"clash\":\"./template/clash.yaml\",\"surge\":\"./template/surge.conf\",\"udp\":false,\"cert\":false}"
        }
        return s
    }
}

struct SublinkBulkResult: Decodable {
    var added: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var failures: [SublinkBulkFailure]?
}

struct SublinkBulkFailure: Decodable, Identifiable {
    var id: String { "\(link)-\(error)" }
    var link: String
    var error: String

    enum CodingKeys: String, CodingKey {
        case link, error
    }
}

/// Some list endpoints wrap as `{ list: [] }` or bare array.
struct SublinkListBox<T: Decodable>: Decodable {
    var list: [T]?
    var items: [T]?
    var nodes: [T]?
    var data: [T]?

    var values: [T] {
        list ?? items ?? nodes ?? data ?? []
    }
}

enum SublinkClientKind: String, CaseIterable, Identifiable {
    case auto
    case clash
    case v2ray
    case surge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动识别"
        case .clash: return "Clash"
        case .v2ray: return "V2Ray"
        case .surge: return "Surge"
        }
    }
}

enum SublinkURLBuilder {
    /// Matches web UI: `{base}/c/?token={md5(subName)}[&client=...]`
    static func clientURL(baseURL: String, subscriptionName: String, client: SublinkClientKind = .auto) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        let token = md5Hex(subscriptionName)
        var url = "\(base)/c/?token=\(token)"
        if client != .auto {
            url += "&client=\(client.rawValue)"
        }
        return url
    }

    static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
