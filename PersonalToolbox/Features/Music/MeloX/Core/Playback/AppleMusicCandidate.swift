import Foundation
import MusicKit

/// Lightweight UI model for Apple Music match picker.
struct AppleMusicCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let duration: TimeInterval?
    let artworkURL: URL?

    init(song: MusicKit.Song) {
        id = song.id.rawValue
        title = song.title
        artistName = song.artistName
        albumTitle = song.albumTitle
        duration = song.duration
        artworkURL = song.artwork?.url(width: 120, height: 120)
    }

    var subtitle: String {
        let parts = [artistName, albumTitle].compactMap { $0 }.filter { !$0.isEmpty }
        if let duration, duration > 0 {
            let m = Int(duration) / 60
            let s = Int(duration) % 60
            return parts.joined(separator: " · ") + String(format: " · %d:%02d", m, s)
        }
        return parts.joined(separator: " · ")
    }
}
