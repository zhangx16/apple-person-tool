import Foundation
import AVFoundation

/// DSP stubs — full MTAudioProcessingTap EQ excluded for Xcode 15.4.
final class SharedAudioEqualizerConfiguration: @unchecked Sendable {
    init(configuration: AudioEqualizerConfiguration) {}
    @MainActor func update(_ configuration: AudioEqualizerConfiguration) {}
}

final class AudioEqualizerProcessor {
    init(configuration: AudioEqualizerConfiguration) {}
    @MainActor func update(configuration: AudioEqualizerConfiguration) {}
    func makeAudioMix(for track: AVAssetTrack) -> AVAudioMix? { nil }
}
