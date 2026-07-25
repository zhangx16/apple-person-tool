import Foundation
import AVFoundation

/// Lightweight EQ stubs (full MTAudioProcessingTap DSP excluded on Xcode 15.4).
final class SharedAudioEqualizerConfiguration: @unchecked Sendable {
    init(configuration: AudioEqualizerConfiguration) {}
    func update(_ configuration: AudioEqualizerConfiguration) {}
}

final class AudioEqualizerProcessor {
    init(configuration: AudioEqualizerConfiguration) {}
    func update(configuration: AudioEqualizerConfiguration) {}
    func makeAudioMix(for track: AVAssetTrack) -> AVAudioMix? { nil }
}
