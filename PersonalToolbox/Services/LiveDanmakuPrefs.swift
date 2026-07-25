import Foundation
import SwiftUI

/// Fullscreen danmaku display preferences (mainstream bullet-screen style).
@MainActor
final class LiveDanmakuPrefs: ObservableObject {
    static let shared = LiveDanmakuPrefs()

    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Keys.fontSize) }
    }
    /// 0…1
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: Keys.opacity) }
    }
    /// Fraction of screen height used for danmaku tracks (0.2…0.9)
    @Published var areaRatio: Double {
        didSet { UserDefaults.standard.set(areaRatio, forKey: Keys.areaRatio) }
    }
    /// Comma / newline separated block words
    @Published var blockWordsRaw: String {
        didSet { UserDefaults.standard.set(blockWordsRaw, forKey: Keys.blockWords) }
    }
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }

    private enum Keys {
        static let fontSize = "live.danmaku.fontSize"
        static let opacity = "live.danmaku.opacity"
        static let areaRatio = "live.danmaku.areaRatio"
        static let blockWords = "live.danmaku.blockWords"
        static let enabled = "live.danmaku.enabled"
    }

    private init() {
        let d = UserDefaults.standard
        fontSize = d.object(forKey: Keys.fontSize) as? Double ?? 15
        opacity = d.object(forKey: Keys.opacity) as? Double ?? 0.92
        areaRatio = d.object(forKey: Keys.areaRatio) as? Double ?? 0.45
        blockWordsRaw = d.string(forKey: Keys.blockWords) ?? ""
        enabled = d.object(forKey: Keys.enabled) as? Bool ?? true
    }

    var blockWords: [String] {
        blockWordsRaw
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func allows(_ text: String) -> Bool {
        let lower = text.lowercased()
        return !blockWords.contains { lower.contains($0.lowercased()) }
    }
}
