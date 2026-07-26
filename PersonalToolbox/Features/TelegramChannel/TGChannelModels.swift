import Foundation

struct TGChannelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var username: String
    var title: String?
    var about: String?
    var updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, username, title, about
        case updatedAt = "updated_at"
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "@\(username)"
    }
}

struct TGChannelListResponse: Codable, Sendable {
    var items: [TGChannelInfo]
}

struct TGPost: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var channelId: String
    var messageId: Int
    var date: Double?
    var text: String?
    var mediaType: String?
    var hasVideo: Bool
    var duration: Double?
    var width: Int?
    var height: Int?
    var fileSize: Int?
    var fileName: String?
    var mimeType: String?
    var externalUrls: [String]
    var channelUsername: String?
    var playPath: String?
    var tgLink: String?

    enum CodingKeys: String, CodingKey {
        case id, date, text, duration, width, height
        case channelId = "channel_id"
        case messageId = "message_id"
        case mediaType = "media_type"
        case hasVideo = "has_video"
        case fileSize = "file_size"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case externalUrls = "external_urls"
        case channelUsername = "channel_username"
        case playPath = "play_path"
        case tgLink = "tg_link"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        channelId = try c.decode(String.self, forKey: .channelId)
        messageId = try c.decode(Int.self, forKey: .messageId)
        date = try c.decodeIfPresent(Double.self, forKey: .date)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        hasVideo = try c.decodeIfPresent(Bool.self, forKey: .hasVideo) ?? false
        if let d = try c.decodeIfPresent(Double.self, forKey: .duration) {
            duration = d
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .duration) {
            duration = Double(i)
        } else {
            duration = nil
        }
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        fileSize = try c.decodeIfPresent(Int.self, forKey: .fileSize)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        externalUrls = try c.decodeIfPresent([String].self, forKey: .externalUrls) ?? []
        channelUsername = try c.decodeIfPresent(String.self, forKey: .channelUsername)
        playPath = try c.decodeIfPresent(String.self, forKey: .playPath)
        tgLink = try c.decodeIfPresent(String.self, forKey: .tgLink)
    }

    var titleLine: String {
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return hasVideo ? (fileName ?? "视频") : "动态"
        }
        return t.replacingOccurrences(of: "\n", with: " ")
    }

    var dateText: String {
        guard let date else { return "" }
        let d = Date(timeIntervalSince1970: date)
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    var durationText: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var fileSizeText: String? {
        guard let fileSize, fileSize > 0 else { return nil }
        let mb = Double(fileSize) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        if mb >= 1 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.0f KB", Double(fileSize) / 1024)
    }
}

struct TGPostListResponse: Codable, Sendable {
    var items: [TGPost]
    var total: Int?
    var username: String?
}

struct TGHealth: Codable, Sendable {
    var ok: Bool?
    var authorized: Bool?
    var channels: [String]?
    var lastError: String?
}
