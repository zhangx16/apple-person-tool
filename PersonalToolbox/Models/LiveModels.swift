import Foundation

enum LivePlatform: String, CaseIterable, Identifiable, Hashable, Codable {
    case huya
    case douyu
    case douyin
    case kuaishou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .huya: return "虎牙"
        case .douyu: return "斗鱼"
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        }
    }

    var systemImage: String {
        switch self {
        case .huya: return "gamecontroller.fill"
        case .douyu: return "tv.fill"
        case .douyin: return "music.note"
        case .kuaishou: return "video.fill"
        }
    }

    var brandAssetName: String {
        switch self {
        case .huya: return "IconLiveHuya"
        case .douyu: return "IconLiveDouyu"
        case .douyin: return "IconLiveDouyinLive"
        case .kuaishou: return "IconLiveKuaishou"
        }
    }

    /// Sites that historically only expose FLV (VLC required for in-app play).
    var isFLVPrimary: Bool {
        switch self {
        case .huya, .douyu, .kuaishou: return true
        case .douyin: return false
        }
    }

    var webHostHint: String {
        switch self {
        case .huya: return "huya.com"
        case .douyu: return "douyu.com"
        case .douyin: return "live.douyin.com"
        case .kuaishou: return "live.kuaishou.com"
        }
    }
}

struct LiveRoomItem: Identifiable, Hashable {
    var id: String { "\(platform.rawValue)-\(roomId)" }
    var platform: LivePlatform
    var roomId: String
    var title: String
    /// Room cover / screenshot (16:9 poster).
    var cover: String
    var userName: String
    var online: Int
    /// Streamer profile avatar (prefer for list rows).
    var userAvatar: String = ""

    /// Prefer homepage avatar; fall back to room cover.
    var displayAvatar: String {
        let a = userAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return cover
    }
}

struct LiveRoomDetail: Hashable {
    var platform: LivePlatform
    var roomId: String
    var title: String
    var cover: String
    var userName: String
    var userAvatar: String
    var online: Int
    var isLive: Bool
    var webURL: String
    var introduction: String
    var playContextJSON: String = "{}"
    var danmakuJSON: String = "{}"
}

struct LiveCategory: Identifiable, Hashable {
    var id: String
    var name: String
    var children: [LiveSubCategory]
}

struct LiveSubCategory: Identifiable, Hashable {
    var id: String
    var name: String
    var parentId: String
    var pic: String = ""
}

struct LiveChatMessage: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var userName: String
    var text: String
    var colorHex: UInt32 = 0xFFFFFF
}

struct LivePlayQuality: Identifiable, Hashable {
    var id: String
    var name: String
    var qn: Int
    var readyURLs: [String] = []
    var bitRate: Int? = nil
    var cdns: [String] = []
    var formBody: String? = nil

    init(
        id: String? = nil,
        name: String,
        qn: Int,
        readyURLs: [String] = [],
        bitRate: Int? = nil,
        cdns: [String] = [],
        formBody: String? = nil
    ) {
        self.id = id ?? "\(qn)-\(name)"
        self.name = name
        self.qn = qn
        self.readyURLs = readyURLs
        self.bitRate = bitRate
        self.cdns = cdns
        self.formBody = formBody
    }
}

struct LivePlayResult: Hashable {
    var urls: [String]
    var headers: [String: String]
}

/// Shared site façade used by Live UI.
enum LiveSiteRouter {
    static func search(platform: LivePlatform, keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        switch platform {
        case .huya: return try await HuyaLiveService.shared.searchRooms(keyword: keyword, page: page)
        case .douyu: return try await DouyuLiveService.shared.searchRooms(keyword: keyword, page: page)
        case .douyin: return try await DouyinLiveService.shared.searchRooms(keyword: keyword, page: page)
        case .kuaishou: return try await KuaishouLiveService.shared.searchRooms(keyword: keyword, page: page)
        }
    }

    static func roomDetail(platform: LivePlatform, roomId: String) async throws -> LiveRoomDetail {
        switch platform {
        case .huya: return try await HuyaLiveService.shared.getRoomDetail(roomId: roomId)
        case .douyu: return try await DouyuLiveService.shared.getRoomDetail(roomId: roomId)
        case .douyin: return try await DouyinLiveService.shared.getRoomDetail(roomId: roomId)
        case .kuaishou: return try await KuaishouLiveService.shared.getRoomDetail(roomId: roomId)
        }
    }

    static func playQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        switch detail.platform {
        case .huya: return try await HuyaLiveService.shared.getPlayQualities(detail: detail)
        case .douyu: return try await DouyuLiveService.shared.getPlayQualities(detail: detail)
        case .douyin: return try await DouyinLiveService.shared.getPlayQualities(detail: detail)
        case .kuaishou: return try await KuaishouLiveService.shared.getPlayQualities(detail: detail)
        }
    }

    static func playURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        switch detail.platform {
        case .huya:
            return try await HuyaLiveService.shared.getPlayURLs(detail: detail, quality: quality)
        case .douyu:
            return try await DouyuLiveService.shared.getPlayURLs(detail: detail, quality: quality)
        case .douyin:
            return try await DouyinLiveService.shared.getPlayURLs(detail: detail, quality: quality)
        case .kuaishou:
            return try await KuaishouLiveService.shared.getPlayURLs(detail: detail, quality: quality)
        }
    }
}

enum LiveJSON {
    static func object(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    static func array(_ any: Any?) -> [[String: Any]]? {
        if let a = any as? [[String: Any]] { return a }
        if let a = any as? [Any] { return a.compactMap { $0 as? [String: Any] } }
        return nil
    }

    static func string(_ any: Any?) -> String {
        guard let any, !(any is NSNull) else { return "" }
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if let i = any as? Int { return "\(i)" }
        if let d = any as? Double { return String(d) }
        return String(describing: any)
    }

    static func encodeJSONSafe(_ dict: [String: Any]) -> String {
        let cleaned = sanitize(dict)
        guard JSONSerialization.isValidJSONObject(cleaned),
              let data = try? JSONSerialization.data(withJSONObject: cleaned, options: []),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private static func sanitize(_ value: Any) -> Any {
        if value is NSNull { return NSNull() }
        if value is String || value is Int || value is Double || value is Bool || value is NSNumber {
            return value
        }
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = sanitize(v) }
            return out
        }
        if let arr = value as? [Any] {
            return arr.map { sanitize($0) }
        }
        return string(value)
    }

    static func int(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return Int(string(any)) ?? 0
    }

    static func encode(_ dict: [String: Any]) -> String {
        encodeJSONSafe(dict)
    }

    static func decodeObject(_ s: String) -> [String: Any] {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }
}
