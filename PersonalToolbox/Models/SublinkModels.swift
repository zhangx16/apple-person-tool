import Foundation

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

struct SublinkNode: Decodable, Identifiable {
    var id: Int { nodeId ?? name.hashValue }
    var nodeId: Int?
    var name: String?
    var link: String?

    enum CodingKeys: String, CodingKey {
        case name, link
        case nodeId = "ID"
        case Name, Link, id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodeId = (try? c.decodeIfPresent(Int.self, forKey: .nodeId))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .id))
        name = (try? c.decodeIfPresent(String.self, forKey: .Name))
            ?? (try? c.decodeIfPresent(String.self, forKey: .name))
        link = (try? c.decodeIfPresent(String.self, forKey: .Link))
            ?? (try? c.decodeIfPresent(String.self, forKey: .link))
    }
}

struct SublinkSub: Decodable, Identifiable {
    var id: Int { subId ?? name.hashValue }
    var subId: Int?
    var name: String?
    var config: String?

    enum CodingKeys: String, CodingKey {
        case name, config
        case subId = "ID"
        case Name, Config, id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subId = (try? c.decodeIfPresent(Int.self, forKey: .subId))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .id))
        name = (try? c.decodeIfPresent(String.self, forKey: .Name))
            ?? (try? c.decodeIfPresent(String.self, forKey: .name))
        config = (try? c.decodeIfPresent(String.self, forKey: .Config))
            ?? (try? c.decodeIfPresent(String.self, forKey: .config))
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
