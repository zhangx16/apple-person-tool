import Foundation
import SwiftUI

// MARK: - Domain (aligned with iamwaa/Scripting 二维码助手)

struct QRRecord: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var content: String
    var timestamp: TimeInterval
    var type: QRRecordType

    init(
        id: String = UUID().uuidString,
        content: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        type: QRRecordType
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.type = type
    }

    var date: Date { Date(timeIntervalSince1970: timestamp) }
}

enum QRRecordType: String, Codable, Sendable {
    case scan = "SCAN"
    case generate = "GENERATE"

    var label: String {
        switch self {
        case .scan: return "扫码"
        case .generate: return "生成"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: return "qrcode.viewfinder"
        case .generate: return "plus.app"
        }
    }
}

enum QRScanMode: String, CaseIterable, Identifiable, Sendable {
    case single
    case continuous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "单次"
        case .continuous: return "连续"
        }
    }
}

struct QRRedirectRule: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var keyword: String
    var urlScheme: String
    var appName: String
    var iconUrl: String?
    var source: RuleSource

    enum RuleSource: String, Codable, Sendable {
        case local
        case remote
    }

    init(
        id: String = UUID().uuidString,
        keyword: String,
        urlScheme: String,
        appName: String,
        iconUrl: String? = nil,
        source: RuleSource = .local
    ) {
        self.id = id
        self.keyword = keyword
        self.urlScheme = urlScheme
        self.appName = appName
        self.iconUrl = iconUrl
        self.source = source
    }

    /// Decode flexible JSON (Scripting export may omit id/source).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        keyword = try c.decode(String.self, forKey: .keyword)
        urlScheme = try c.decode(String.self, forKey: .urlScheme)
        appName = try c.decode(String.self, forKey: .appName)
        iconUrl = try c.decodeIfPresent(String.self, forKey: .iconUrl)
        source = try c.decodeIfPresent(RuleSource.self, forKey: .source) ?? .local
    }
}

struct QRAssistantSettings: Codable, Hashable, Sendable {
    var autoScanOnOpen: Bool
    var autoRedirect: Bool
    var redirectRules: [QRRedirectRule]
    var fallbackEnabled: Bool
    var fallbackUrlScheme: String
    var subscriptionUrl: String

    static let `default` = QRAssistantSettings(
        autoScanOnOpen: false,
        autoRedirect: false,
        redirectRules: QRRedirectDefaults.builtInRules,
        fallbackEnabled: false,
        fallbackUrlScheme: "",
        subscriptionUrl: ""
    )
}

struct QRAssistantData: Codable, Sendable {
    var records: [QRRecord]
    var settings: QRAssistantSettings
    var version: Int

    static let empty = QRAssistantData(records: [], settings: .default, version: 1)
}

enum QRRedirectDefaults {
    /// Brand blue matching original script color rgba(71, 102, 194).
    static let accent = Color(hex: 0x4766C2)

    static let builtInRules: [QRRedirectRule] = [
        QRRedirectRule(
            keyword: "wechat,weixin,wxp,wx,wechatpay,tenpay,micromsg,u.wechat.com,c.weixin.com,payapp.weixin,pay.qq.com,cloud.tencent,login.weixin,open.weixin,QSWchatMiniApp,4XV.CN,x.5dp.top,z.didi.cn",
            urlScheme: "weixin://scanqrcode",
            appName: "微信"
        ),
        QRRedirectRule(
            keyword: "qq,mqq,mqqapi,tencent",
            urlScheme: "mqqapi://qrcode/scan_qrcode?version=1&src_type=app",
            appName: "QQ"
        ),
        QRRedirectRule(
            keyword: "alipay,alipays,zhifubao,koubei,yaoyao.cebbank.com,page.cainiao.com",
            urlScheme: "alipays://platformapi/startapp?saId=10000007",
            appName: "支付宝"
        ),
        QRRedirectRule(
            keyword: "taobao,tmall,tb,itaobao",
            urlScheme: "taobao://tb.cn/n/scancode",
            appName: "淘宝"
        ),
        QRRedirectRule(
            keyword: "douyin,dy,snssdk,amemv,tiktok",
            urlScheme: "snssdk1128://scan",
            appName: "抖音"
        ),
        QRRedirectRule(
            keyword: "jd,jingdong,360buy,openapp.jdmobile",
            urlScheme: "openapp.jdmobile://virtual?params={\"category\":\"jump\",\"des\":\"saoasao\"}",
            appName: "京东"
        ),
        QRRedirectRule(
            keyword: "meituan,mt,dianping",
            urlScheme: "imeituan://www.meituan.com/scanQRCode?openAR=1",
            appName: "美团"
        ),
        QRRedirectRule(
            keyword: "xhslink.com",
            urlScheme: "xhsdiscover://scan",
            appName: "小红书"
        ),
        QRRedirectRule(
            keyword: "login.xuexi.cn",
            urlScheme: "dtxuexi://appclient/page/study_feeds?url={content}",
            appName: "学习强国"
        )
    ]
}

enum QRRedirectEngine {
    static func match(content: String, rules: [QRRedirectRule]) -> QRRedirectRule? {
        let lower = content.lowercased()
        for rule in rules {
            let keywords = rule.keyword
                .split(whereSeparator: { $0 == "," || $0 == "，" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if keywords.contains(where: { lower.contains($0) }) {
                return rule
            }
        }
        return nil
    }

    static func mergeRemote(local: [QRRedirectRule], remote: [QRRedirectRule]) -> [QRRedirectRule] {
        var merged = local.map { rule -> QRRedirectRule in
            var r = rule
            if r.source != .remote { r.source = .local }
            return r
        }
        for remoteRule in remote {
            let exists = merged.contains {
                $0.keyword.lowercased() == remoteRule.keyword.lowercased()
                    && $0.urlScheme == remoteRule.urlScheme
            }
            if !exists {
                var r = remoteRule
                r.source = .remote
                merged.append(r)
            }
        }
        return merged
    }

    /// Expand placeholders in scheme templates.
    static func resolveScheme(_ template: String, content: String) -> URL? {
        let encoded = content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? content
        let raw = template
            .replacingOccurrences(of: "{content}", with: encoded)
            .replacingOccurrences(of: "{url}", with: encoded)
        return URL(string: raw) ?? URL(string: template)
    }

    static func openableHTTPURL(from content: String) -> URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: trimmed), let scheme = u.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return u
        }
        if trimmed.hasPrefix("www."), let u = URL(string: "https://\(trimmed)") {
            return u
        }
        return nil
    }
}
