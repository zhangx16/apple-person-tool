import Foundation

struct PlaybackSource: Equatable, Sendable {
    let url: URL
    let bitrate: Int?
    let format: String?
    /// Netease free-trial / VIP preview clip (usually ~30s), not the full track.
    var isTrialPreview: Bool = false
}
