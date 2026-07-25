import Foundation
import SwiftUI

/// Vertical band for flying danmaku (参考 simple_live 显示区域 + 对齐).
enum LiveDanmakuVerticalAlign: String, CaseIterable, Identifiable, Sendable {
    case top
    case center
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: "顶部"
        case .center: "居中"
        case .bottom: "底部"
        }
    }

    var systemImage: String {
        switch self {
        case .top: "align.vertical.top"
        case .center: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }
}

/// Fullscreen / portrait danmaku preferences (参考 dart_simple_live 弹幕设置).
@MainActor
final class LiveDanmakuPrefs: ObservableObject {
    static let shared = LiveDanmakuPrefs()

    /// Master display switch (synced with room toggle when possible).
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }

    /// When false, block words / users are ignored.
    @Published var shieldEnabled: Bool {
        didSet { UserDefaults.standard.set(shieldEnabled, forKey: Keys.shieldEnabled) }
    }

    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Keys.fontSize) }
    }

    /// 0.1…1 text alpha
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: Keys.opacity) }
    }

    /// Fraction of screen height used for flying tracks (0.15…1.0)
    @Published var areaRatio: Double {
        didSet { UserDefaults.standard.set(areaRatio, forKey: Keys.areaRatio) }
    }

    /// Where the area band sits vertically.
    @Published var verticalAlign: LiveDanmakuVerticalAlign {
        didSet { UserDefaults.standard.set(verticalAlign.rawValue, forKey: Keys.verticalAlign) }
    }

    /// Scroll duration in seconds (smaller = faster). 4…18
    @Published var speedDuration: Double {
        didSet { UserDefaults.standard.set(speedDuration, forKey: Keys.speedDuration) }
    }

    /// Preferred track count; 0 = auto from area/font.
    @Published var maxTracks: Int {
        didSet { UserDefaults.standard.set(maxTracks, forKey: Keys.maxTracks) }
    }

    @Published var showUsername: Bool {
        didSet { UserDefaults.standard.set(showUsername, forKey: Keys.showUsername) }
    }

    @Published var strokeEnabled: Bool {
        didSet { UserDefaults.standard.set(strokeEnabled, forKey: Keys.strokeEnabled) }
    }

    /// Comma / newline separated keyword shields
    @Published var blockWordsRaw: String {
        didSet { UserDefaults.standard.set(blockWordsRaw, forKey: Keys.blockWords) }
    }

    /// Comma / newline separated user name shields
    @Published var blockUsersRaw: String {
        didSet { UserDefaults.standard.set(blockUsersRaw, forKey: Keys.blockUsers) }
    }

    private enum Keys {
        static let enabled = "live.danmaku.enabled"
        static let shieldEnabled = "live.danmaku.shieldEnabled"
        static let fontSize = "live.danmaku.fontSize"
        static let opacity = "live.danmaku.opacity"
        static let areaRatio = "live.danmaku.areaRatio"
        static let verticalAlign = "live.danmaku.verticalAlign"
        static let speedDuration = "live.danmaku.speedDuration"
        static let maxTracks = "live.danmaku.maxTracks"
        static let showUsername = "live.danmaku.showUsername"
        static let strokeEnabled = "live.danmaku.strokeEnabled"
        static let blockWords = "live.danmaku.blockWords"
        static let blockUsers = "live.danmaku.blockUsers"
    }

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: Keys.enabled) as? Bool ?? true
        shieldEnabled = d.object(forKey: Keys.shieldEnabled) as? Bool ?? true
        fontSize = d.object(forKey: Keys.fontSize) as? Double ?? 15
        opacity = d.object(forKey: Keys.opacity) as? Double ?? 0.92
        areaRatio = d.object(forKey: Keys.areaRatio) as? Double ?? 0.45
        if let raw = d.string(forKey: Keys.verticalAlign),
           let align = LiveDanmakuVerticalAlign(rawValue: raw) {
            verticalAlign = align
        } else {
            verticalAlign = .top
        }
        speedDuration = d.object(forKey: Keys.speedDuration) as? Double ?? 8
        maxTracks = d.object(forKey: Keys.maxTracks) as? Int ?? 0
        showUsername = d.object(forKey: Keys.showUsername) as? Bool ?? true
        strokeEnabled = d.object(forKey: Keys.strokeEnabled) as? Bool ?? true
        blockWordsRaw = d.string(forKey: Keys.blockWords) ?? ""
        blockUsersRaw = d.string(forKey: Keys.blockUsers) ?? ""
    }

    var blockWords: [String] { Self.splitList(blockWordsRaw) }
    var blockUsers: [String] { Self.splitList(blockUsersRaw) }

    func addBlockWord(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        var list = blockWords
        guard !list.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) else { return }
        list.append(w)
        blockWordsRaw = list.joined(separator: ",")
    }

    func removeBlockWord(_ word: String) {
        blockWordsRaw = blockWords
            .filter { $0.caseInsensitiveCompare(word) != .orderedSame }
            .joined(separator: ",")
    }

    func addBlockUser(_ name: String) {
        let w = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        var list = blockUsers
        guard !list.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) else { return }
        list.append(w)
        blockUsersRaw = list.joined(separator: ",")
    }

    func removeBlockUser(_ name: String) {
        blockUsersRaw = blockUsers
            .filter { $0.caseInsensitiveCompare(name) != .orderedSame }
            .joined(separator: ",")
    }

    /// Whether a chat line should be shown.
    func allows(userName: String, text: String) -> Bool {
        guard shieldEnabled else { return true }
        let user = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty,
           blockUsers.contains(where: { user.localizedCaseInsensitiveContains($0) }) {
            return false
        }
        let body = text.lowercased()
        if blockWords.contains(where: { body.contains($0.lowercased()) }) {
            return false
        }
        return true
    }

    /// Resolved track count for a given height.
    func resolvedTrackCount(containerHeight: CGFloat) -> Int {
        let areaH = max(40, containerHeight * areaRatio)
        let auto = max(3, min(14, Int(areaH / max(fontSize + 8, 18))))
        if maxTracks <= 0 { return auto }
        return max(1, min(maxTracks, auto))
    }

    private static func splitList(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" || $0 == ";" || $0 == "；" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
