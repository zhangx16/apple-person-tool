import Foundation

struct PlaybackIssue: Identifiable, Sendable {
    let id = UUID()
    let message: String

    init(song: Song, error: Error) {
        if let apiError = error as? APIError {
            switch apiError {
            case .noPlayableSource:
                message = "《\(song.name)》可能因版权或地区限制，当前没有可用的播放地址。"
                return
            case .trialPreviewOnly:
                message = "《\(song.name)》在网易云仅可试听片段（未开会员），无法听完整首。"
                return
            default:
                break
            }
        }

        if let playbackError = error as? AudioPlaybackError,
           case .itemFailed = playbackError {
            message = "《\(song.name)》的音源无法载入，可能因版权、地区限制或网络问题。"
            return
        }

        message = "《\(song.name)》播放失败：\(error.localizedDescription)"
    }
}
