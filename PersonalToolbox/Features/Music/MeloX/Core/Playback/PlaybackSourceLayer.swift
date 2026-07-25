import Foundation

/// Active audio path — used for status UI and failure-chain messaging.
enum PlaybackSourceLayer: String, Sendable {
    case none
    case localDownload
    case neteaseFull
    case neteaseTrial
    case navidrome

    var title: String {
        switch self {
        case .none: "无"
        case .localDownload: "本地下载"
        case .neteaseFull: "网易云"
        case .neteaseTrial: "网易云试听"
        case .navidrome: "Navidrome"
        }
    }
}
