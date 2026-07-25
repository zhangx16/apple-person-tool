import Foundation

struct PlaybackIssue: Identifiable, Sendable {
    let id = UUID()
    let message: String

    init(song: Song, error: Error, alternateSourceError: Error? = nil) {
        var base: String
        if let apiError = error as? APIError {
            switch apiError {
            case .noPlayableSource:
                base = "《\(song.name)》可能因版权或地区限制，当前没有可用的网易云播放地址。"
            case .trialPreviewOnly:
                base = "《\(song.name)》在网易云仅可试听片段（未开会员），无法听完整首。"
            default:
                base = "《\(song.name)》播放失败：\(error.localizedDescription)"
            }
        } else if let playbackError = error as? AudioPlaybackError,
                  case .itemFailed = playbackError {
            base = "《\(song.name)》的网易云音源无法载入，可能因版权、地区限制或网络问题。"
        } else if error is NavidromeClient.ClientError {
            base = "《\(song.name)》\(error.localizedDescription)"
        } else {
            base = "《\(song.name)》播放失败：\(error.localizedDescription)"
        }

        if let alternateSourceError {
            base += "\nNavidrome：\(alternateSourceError.localizedDescription)"
        }
        message = base
    }

    init(song: Song, message: String) {
        self.message = "《\(song.name)》\(message)"
    }
}
