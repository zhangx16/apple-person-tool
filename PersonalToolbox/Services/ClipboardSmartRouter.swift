import Foundation
import UIKit

/// Recognize actionable content from the system pasteboard / free text.
enum ClipboardSmartKind: String, Hashable {
    case liveRoom
    case videoDownload
    case musicNetease
    case ipAddress
    case expressTracking
    case subscriptionURL
    case genericURL
}

struct ClipboardSmartHit: Identifiable, Hashable {
    var id: String { "\(kind.rawValue)-\(payload)" }
    var kind: ClipboardSmartKind
    var title: String
    var subtitle: String
    var payload: String
    var systemImage: String
    var tintHex: UInt32
}

enum ClipboardSmartRouter {
    /// Parse free text (clipboard or share).
    static func detect(_ raw: String) -> ClipboardSmartHit? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else { return nil }

        // Live room URLs / ids
        if let live = detectLive(text) { return live }
        // Netease music
        if let music = detectMusic(text) { return music }
        // Video download platforms
        if let video = detectVideo(text) { return video }
        // IPv4
        if let ip = detectIP(text) { return ip }
        // Express tracking (digits-heavy)
        if let exp = detectExpress(text) { return exp }
        // Subscription / clash style
        if text.lowercased().contains("clash") || text.lowercased().contains("v2ray")
            || text.contains("sub://") || text.contains("/subscribe") {
            return ClipboardSmartHit(
                kind: .subscriptionURL,
                title: "订阅 / 节点链接",
                subtitle: "可到 Sublink 或节点包使用",
                payload: text,
                systemImage: "link.circle.fill",
                tintHex: 0x0A84FF
            )
        }
        // Generic http(s)
        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
            return ClipboardSmartHit(
                kind: .genericURL,
                title: "网页链接",
                subtitle: String(text.prefix(48)),
                payload: text,
                systemImage: "safari",
                tintHex: 0x8E8E93
            )
        }
        return nil
    }

    static func currentPasteboardHit() -> ClipboardSmartHit? {
        guard let s = UIPasteboard.general.string else { return nil }
        return detect(s)
    }

    // MARK: - Detectors

    private static func detectLive(_ text: String) -> ClipboardSmartHit? {
        let lower = text.lowercased()
        let patterns: [(String, LivePlatform)] = [
            ("live.bilibili.com", .bilibili),
            ("bilibili.com/h5/", .bilibili),
            ("m.huya.com", .huya),
            ("huya.com", .huya),
            ("m.douyu.com", .douyu),
            ("douyu.com", .douyu),
            ("live.douyin.com", .douyin),
            ("live.kuaishou.com", .kuaishou)
        ]
        for (needle, platform) in patterns where lower.contains(needle) {
            let rid = extractTrailingID(text) ?? text
            return ClipboardSmartHit(
                kind: .liveRoom,
                title: "\(platform.title) 直播间",
                subtitle: "房间 \(rid)",
                payload: "\(platform.rawValue)|\(rid)",
                systemImage: "play.tv.fill",
                tintHex: 0xFF375F
            )
        }
        // Pure room-ish id with platform hint words
        return nil
    }

    private static func detectMusic(_ text: String) -> ClipboardSmartHit? {
        let lower = text.lowercased()
        guard lower.contains("music.163.com") || lower.contains("163cn.tv") || lower.contains("y.music.163.com") else {
            return nil
        }
        var subtitle = "在音乐模块打开"
        if let id = firstCapture(text, pattern: #"[?&]id=(\d+)"#) {
            if lower.contains("playlist") {
                subtitle = "歌单 id \(id)"
            } else if lower.contains("song") || lower.contains("/song") {
                subtitle = "歌曲 id \(id)"
            } else if lower.contains("album") {
                subtitle = "专辑 id \(id)"
            } else {
                subtitle = "id \(id)"
            }
        }
        return ClipboardSmartHit(
            kind: .musicNetease,
            title: "网易云音乐",
            subtitle: subtitle,
            payload: text,
            systemImage: "music.note",
            tintHex: 0xE11D48
        )
    }

    private static func firstCapture(_ text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func detectVideo(_ text: String) -> ClipboardSmartHit? {
        let lower = text.lowercased()
        let hosts = ["youtube.com", "youtu.be", "bilibili.com/video", "b23.tv", "douyin.com", "v.douyin.com", "tiktok.com"]
        guard hosts.contains(where: { lower.contains($0) }) else { return nil }
        return ClipboardSmartHit(
            kind: .videoDownload,
            title: "视频链接",
            subtitle: "可加入下载队列",
            payload: text,
            systemImage: "arrow.down.circle.fill",
            tintHex: 0xFF3B30
        )
    }

    private static func detectIP(_ text: String) -> ClipboardSmartHit? {
        // Single IPv4 token
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) else {
            return nil
        }
        let ip = String(trimmed[range])
        return ClipboardSmartHit(
            kind: .ipAddress,
            title: "IP 地址",
            subtitle: ip,
            payload: ip,
            systemImage: "antenna.radiowaves.left.and.right",
            tintHex: 0xAE6DD8
        )
    }

    private static func detectExpress(_ text: String) -> ClipboardSmartHit? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        // 10–20 alnum tracking-ish
        guard let r = compact.range(of: #"^[A-Za-z0-9]{10,20}$"#, options: .regularExpression) else {
            return nil
        }
        let code = String(compact[r])
        let digits = code.filter(\.isNumber).count
        guard digits >= 8 else { return nil }
        return ClipboardSmartHit(
            kind: .expressTracking,
            title: "快递单号",
            subtitle: code,
            payload: code,
            systemImage: "shippingbox.fill",
            tintHex: 0xAC8E68
        )
    }

    private static func extractTrailingID(_ text: String) -> String? {
        if let r = text.range(of: #"/(\d{3,})(?:\?|$|/)"#, options: .regularExpression) {
            let s = String(text[r]).filter(\.isNumber)
            if !s.isEmpty { return s }
        }
        if let r = text.range(of: #"\d{5,}"#, options: .regularExpression) {
            return String(text[r])
        }
        return nil
    }
}
