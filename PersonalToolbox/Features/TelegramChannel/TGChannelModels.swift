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

struct TGCreatorInfo: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var count: Int?

    var id: String { name }
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
    /// Server has fully cached this video on VPS disk.
    var cached: Bool
    var cacheBytes: Int64?
    /// Uploader / series label (e.g. 小约翰可汗、脑洞乌托邦).
    var creator: String?

    enum CodingKeys: String, CodingKey {
        case id, date, text, duration, width, height, creator
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
        case cached
        case cacheBytes = "cache_bytes"
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
        cached = try c.decodeIfPresent(Bool.self, forKey: .cached) ?? false
        if let i64 = try c.decodeIfPresent(Int64.self, forKey: .cacheBytes) {
            cacheBytes = i64
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .cacheBytes) {
            cacheBytes = Int64(i)
        } else {
            cacheBytes = nil
        }
        let cname = try c.decodeIfPresent(String.self, forKey: .creator)
        if let cname, !cname.isEmpty {
            creator = cname
        } else {
            creator = Self.inferCreator(text: text, fileName: fileName)
        }
    }

    /// Client-side fallback if API is older.
    static func inferCreator(text: String?, fileName: String?) -> String {
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let generic: Set<String> = [
            "b站付费", "b站", "油管", "youtube", "会员", "付费", "更新", "置顶", "合作", "投稿",
        ]
        // Hashtags
        if let regex = try? NSRegularExpression(pattern: #"#([^\s#【\[\]\|,，。！!？?]+)"#) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                guard m.numberOfRanges > 1 else { continue }
                let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let low = name.lowercased()
                if generic.contains(low) || name.contains("付费") || name.contains("会员") { continue }
                if name.count > 40 || name.isEmpty { continue }
                return name
            }
        }
        let first = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        if !first.isEmpty {
            var s = first
            s = s.replacingOccurrences(of: #"【[^】]*】"#, with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
            if let r = s.range(of: #"\s*[-—|｜]\s*"#, options: .regularExpression) {
                s = String(s[..<r.lowerBound])
            }
            s = s.replacingOccurrences(of: #"\d{4}[-/.]\d{1,2}[-/.]\d{1,2}.*"#, with: "", options: .regularExpression)
            s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-—|｜")))
            if s.count > 1, s.count <= 32 { return s }
        }
        if let fileName, !fileName.isEmpty {
            let stem = (fileName as NSString).deletingPathExtension
            let part = stem.components(separatedBy: CharacterSet(charactersIn: "-—_")).first ?? stem
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.count > 1, t.count <= 32 { return t }
        }
        return "未分类"
    }

    var creatorName: String {
        if let creator, !creator.isEmpty { return creator }
        return Self.inferCreator(text: text, fileName: fileName)
    }

    /// Short title without footer noise.
    var displayTitle: String {
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return hasVideo ? (fileName ?? "视频") : "动态"
        }
        var lines = t.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Drop tag / CTA footers.
        lines = lines.filter { line in
            if line.hasPrefix("标签") { return false }
            if line.contains("合作/投稿") || line.contains("网盘自行") { return false }
            if line.contains("回到播放列表") { return false }
            return true
        }
        let joined = lines.prefix(2).joined(separator: " ")
        return joined.isEmpty ? titleLine : joined
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
        Self.formatBytes(fileSize.map { Int64($0) })
    }

    var cacheSizeText: String? {
        guard cached else { return nil }
        return Self.formatBytes(cacheBytes)
    }

    static func formatBytes(_ n: Int64?) -> String? {
        guard let n, n > 0 else { return nil }
        let mb = Double(n) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        if mb >= 1 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.0f KB", Double(n) / 1024)
    }
}

struct TGPostListResponse: Codable, Sendable {
    var items: [TGPost]
    var total: Int?
    var username: String?
    var creators: [TGCreatorInfo]?
    var cacheTotalBytes: Int64?
    var cacheFileCount: Int?

    enum CodingKeys: String, CodingKey {
        case items, total, username, creators
        case cacheTotalBytes = "cache_total_bytes"
        case cacheFileCount = "cache_file_count"
    }
}

struct TGCacheStats: Codable, Sendable {
    var ok: Bool?
    var fileCount: Int?
    var totalBytes: Int64?
    var mediaDir: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case fileCount = "file_count"
        case totalBytes = "total_bytes"
        case mediaDir = "media_dir"
    }
}

struct TGCacheDeleteResult: Codable, Sendable {
    var ok: Bool?
    var deleted: Bool?
    var freedBytes: Int64?
    var removedCount: Int?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case ok, deleted, reason
        case freedBytes = "freed_bytes"
        case removedCount = "removed_count"
    }
}

struct TGHealth: Codable, Sendable {
    var ok: Bool?
    var authorized: Bool?
    var channels: [String]?
    var lastError: String?
}
