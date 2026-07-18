import Foundation

enum LivePlatform: String, CaseIterable, Identifiable, Hashable {
    case bilibili
    case huya
    case douyu
    case douyin
    case kuaishou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bilibili: return "哔哩哔哩"
        case .huya: return "虎牙"
        case .douyu: return "斗鱼"
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        }
    }

    var systemImage: String {
        switch self {
        case .bilibili: return "play.rectangle.fill"
        case .huya: return "gamecontroller.fill"
        case .douyu: return "fish.fill"
        case .douyin: return "music.note.tv.fill"
        case .kuaishou: return "video.fill"
        }
    }

    /// Ported from SimpleLive core v1.12.6 (+ Kuaishou mobile page).
    var isImplemented: Bool { true }

    var webHostHint: String {
        switch self {
        case .bilibili: return "live.bilibili.com"
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
    var cover: String
    var userName: String
    var online: Int
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
    /// Opaque JSON for play resolution (signed args / lines / stream_url).
    var playContextJSON: String = "{}"
    /// Opaque JSON for danmaku connection (token / host / sid).
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
    /// Bilibili qn / sort key / rate index.
    var qn: Int
    /// Pre-resolved play URLs (Douyin / Kuaishou / sometimes Huya).
    var readyURLs: [String] = []
    /// Huya bitRate (0 = source).
    var bitRate: Int? = nil
    /// Douyu CDN list for this rate.
    var cdns: [String] = []
    /// Douyu signed form body (without cdn/rate).
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
    static func recommend(platform: LivePlatform, page: Int = 1) async throws -> [LiveRoomItem] {
        switch platform {
        case .bilibili: return try await BilibiliLiveService.shared.getRecommendRooms(page: page)
        case .huya: return try await HuyaLiveService.shared.getRecommendRooms(page: page)
        case .douyu: return try await DouyuLiveService.shared.getRecommendRooms(page: page)
        case .douyin: return try await DouyinLiveService.shared.getRecommendRooms(page: page)
        case .kuaishou: return try await KuaishouLiveService.shared.getRecommendRooms(page: page)
        }
    }

    static func search(platform: LivePlatform, keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        switch platform {
        case .bilibili: return try await BilibiliLiveService.shared.searchRooms(keyword: keyword, page: page)
        case .huya: return try await HuyaLiveService.shared.searchRooms(keyword: keyword, page: page)
        case .douyu: return try await DouyuLiveService.shared.searchRooms(keyword: keyword, page: page)
        case .douyin: return try await DouyinLiveService.shared.searchRooms(keyword: keyword, page: page)
        case .kuaishou: return try await KuaishouLiveService.shared.searchRooms(keyword: keyword, page: page)
        }
    }

    static func roomDetail(platform: LivePlatform, roomId: String) async throws -> LiveRoomDetail {
        switch platform {
        case .bilibili: return try await BilibiliLiveService.shared.getRoomDetail(roomId: roomId)
        case .huya: return try await HuyaLiveService.shared.getRoomDetail(roomId: roomId)
        case .douyu: return try await DouyuLiveService.shared.getRoomDetail(roomId: roomId)
        case .douyin: return try await DouyinLiveService.shared.getRoomDetail(roomId: roomId)
        case .kuaishou: return try await KuaishouLiveService.shared.getRoomDetail(roomId: roomId)
        }
    }

    static func playQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        switch detail.platform {
        case .bilibili: return try await BilibiliLiveService.shared.getPlayQualities(roomId: detail.roomId)
        case .huya: return try await HuyaLiveService.shared.getPlayQualities(detail: detail)
        case .douyu: return try await DouyuLiveService.shared.getPlayQualities(detail: detail)
        case .douyin: return try await DouyinLiveService.shared.getPlayQualities(detail: detail)
        case .kuaishou: return try await KuaishouLiveService.shared.getPlayQualities(detail: detail)
        }
    }

    static func playURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        switch detail.platform {
        case .bilibili:
            return try await BilibiliLiveService.shared.getPlayURLs(roomId: detail.roomId, qn: quality.qn)
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

    static func categories(platform: LivePlatform) async throws -> [LiveCategory] {
        switch platform {
        case .bilibili: return try await BilibiliLiveService.shared.getCategories()
        case .huya: return try await HuyaLiveService.shared.getCategories()
        case .douyu: return try await DouyuLiveService.shared.getCategories()
        case .douyin: return try await DouyinLiveService.shared.getCategories()
        case .kuaishou: return try await KuaishouLiveService.shared.getCategories()
        }
    }

    static func categoryRooms(
        platform: LivePlatform,
        category: LiveSubCategory,
        page: Int = 1
    ) async throws -> [LiveRoomItem] {
        switch platform {
        case .bilibili: return try await BilibiliLiveService.shared.getCategoryRooms(category: category, page: page)
        case .huya: return try await HuyaLiveService.shared.getCategoryRooms(category: category, page: page)
        case .douyu: return try await DouyuLiveService.shared.getCategoryRooms(category: category, page: page)
        case .douyin: return try await DouyinLiveService.shared.getCategoryRooms(category: category, page: page)
        case .kuaishou: return try await KuaishouLiveService.shared.getCategoryRooms(category: category, page: page)
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
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if let i = any as? Int { return "\(i)" }
        if any is NSNull || any == nil { return "" }
        return "\(any!)"
    }

    static func int(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return Int(string(any)) ?? 0
    }

    static func encode(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func decodeObject(_ s: String) -> [String: Any] {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }
}
