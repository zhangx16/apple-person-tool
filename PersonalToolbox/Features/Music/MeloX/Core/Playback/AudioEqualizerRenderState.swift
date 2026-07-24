import Foundation

/// Equalizer snapshot for the audio render thread (iOS 17-safe, no Synchronization.Atomic).
struct AudioEqualizerRenderConfiguration {
    let isEnabled: Bool
    let preamp: Float
    let bandGains: [Float]
    let revision: UInt64

    var isBypassed: Bool {
        guard isEnabled, abs(preamp) > 0.0001 || hasAdjustedBand else {
            return true
        }
        return false
    }

    private var hasAdjustedBand: Bool {
        for index in 0..<min(bandGains.count, AudioEqualizerBand.count)
        where abs(bandGains[index]) > 0.0001 {
            return true
        }
        return false
    }
}

/// Thread-safe shared EQ configuration for player DSP (lock-based).
final class SharedAudioEqualizerConfiguration: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AudioEqualizerRenderConfiguration
    private var revisionCounter: UInt64 = 0

    init(configuration: AudioEqualizerConfiguration) {
        current = Self.renderConfiguration(from: configuration, revision: 0)
    }

    @MainActor
    func update(_ configuration: AudioEqualizerConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        revisionCounter &+= 2
        current = Self.renderConfiguration(
            from: configuration,
            revision: revisionCounter
        )
    }

    func snapshot() -> AudioEqualizerRenderConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    private static func renderConfiguration(
        from configuration: AudioEqualizerConfiguration,
        revision: UInt64
    ) -> AudioEqualizerRenderConfiguration {
        var gains = Array(repeating: Float(0), count: AudioEqualizerBand.count)
        for index in 0..<min(configuration.bandGains.count, AudioEqualizerBand.count) {
            let gain = configuration.bandGains[index]
            gains[index] = Float(
                min(
                    max(
                        gain.isFinite ? gain : 0,
                        AudioEqualizerPreferences.bandGainRange.lowerBound
                    ),
                    AudioEqualizerPreferences.bandGainRange.upperBound
                )
            )
        }

        let preamp = configuration.preamp.isFinite ? configuration.preamp : 0
        return AudioEqualizerRenderConfiguration(
            isEnabled: configuration.isEnabled,
            preamp: Float(
                min(
                    max(
                        preamp,
                        AudioEqualizerPreferences.preampRange.lowerBound
                    ),
                    AudioEqualizerPreferences.preampRange.upperBound
                )
            ),
            bandGains: gains,
            revision: revision
        )
    }
}
