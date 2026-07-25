import Foundation

/// Active audio path — used for status UI and failure-chain messaging.
enum PlaybackSourceLayer: String, Sendable {
    case none
    case localDownload
    case neteaseFull
    case neteaseTrial
    case appleMusic
    /// Opened system Music app (MusicKit developer token unavailable).
    case appleMusicExternal

    var title: String {
        switch self {
        case .none: "无"
        case .localDownload: "本地下载"
        case .neteaseFull: "网易云"
        case .neteaseTrial: "网易云试听"
        case .appleMusic: "Apple Music"
        case .appleMusicExternal: "Apple Music（系统 App）"
        }
    }
}

enum AppleMusicSwitchReason: String, Sendable {
    case manual
    case preferPolicy
    case trialPreview
    case noSource
    case playbackFailed
    case durationProbe

    var countsAsRescue: Bool {
        switch self {
        case .manual: false
        case .preferPolicy, .trialPreview, .noSource, .playbackFailed, .durationProbe: true
        }
    }

    var toastMessage: String {
        switch self {
        case .manual:
            return "已用 Apple Music 播放"
        case .preferPolicy:
            return "优先策略：Apple Music 完整播放"
        case .trialPreview:
            return "已跳过试听，切换 Apple Music 完整版"
        case .noSource:
            return "无可用网易云音源，已用 Apple Music"
        case .playbackFailed:
            return "网易云播放失败，已用 Apple Music"
        case .durationProbe:
            return "已切换到 Apple Music 完整版"
        }
    }

    func statusLine(match: String?) -> String {
        let base: String
        switch self {
        case .manual: base = "Apple Music · 手动"
        case .preferPolicy: base = "Apple Music · 优先策略"
        case .trialPreview: base = "Apple Music · 跳过试听"
        case .noSource: base = "Apple Music · 无网易云源"
        case .playbackFailed: base = "Apple Music · 网易云失败回退"
        case .durationProbe: base = "Apple Music · 时长探测回退"
        }
        if let match, !match.isEmpty {
            return "\(base) · \(match)"
        }
        return base
    }
}
