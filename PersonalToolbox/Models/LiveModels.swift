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

    /// MVP: only Bilibili fully ported; others show “coming soon” with open-in-browser fallback.
    var isImplemented: Bool {
        self == .bilibili
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
}

struct LivePlayQuality: Identifiable, Hashable {
    var id: String { "\(qn)" }
    var name: String
    var qn: Int
}

struct LivePlayResult: Hashable {
    var urls: [String]
    var headers: [String: String]
}
