import Foundation

/// How MeloX chooses between Netease streams and Apple Music (MusicKit).
enum AudioSourcePolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Never use Apple Music automatically (manual long-press still allowed).
    case neteaseOnly
    /// Full Netease first; on no source / trial clip / hard fail → Apple Music.
    case smartFallback
    /// Try Apple Music first when online; fall back to Netease full/trial.
    case preferAppleMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neteaseOnly: "仅网易云"
        case .smartFallback: "智能回退"
        case .preferAppleMusic: "优先 Apple Music"
        }
    }

    var subtitle: String {
        switch self {
        case .neteaseOnly:
            "始终用网易云（含试听）。仍可长按单曲手动切 Apple Music。"
        case .smartFallback:
            "优先完整网易云；无源、仅试听或失败时改用 Apple Music 完整曲。"
        case .preferAppleMusic:
            "有会员时优先 MusicKit 完整播放；失败再回网易云。"
        }
    }

    var systemImage: String {
        switch self {
        case .neteaseOnly: "music.note.list"
        case .smartFallback: "arrow.triangle.2.circlepath"
        case .preferAppleMusic: "apple.logo"
        }
    }

    /// Automatic MusicKit when Netease has no full track / fails.
    var allowsAutomaticAppleMusic: Bool {
        self != .neteaseOnly
    }

    /// Try Apple Music before requesting Netease stream.
    var prefersAppleMusicFirst: Bool {
        self == .preferAppleMusic
    }
}
