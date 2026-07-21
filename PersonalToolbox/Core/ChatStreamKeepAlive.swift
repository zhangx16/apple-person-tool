import AVFoundation
import UIKit

/// Keeps the process eligible for background execution while chat streams run.
///
/// iOS will suspend normal apps within seconds of leaving the foreground, which kills
/// in-flight SSE. With `UIBackgroundModes = audio` + a near-silent looping player, the
/// app stays active and network streams can finish (personal / Ad Hoc toolbox use).
@MainActor
final class ChatStreamKeepAlive: NSObject {
    static let shared = ChatStreamKeepAlive()

    private var retainCount = 0
    private var player: AVAudioPlayer?
    private var sessionConfigured = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    /// Call when a chat stream starts.
    func retain() {
        retainCount += 1
        startIfNeeded()
    }

    /// Call when a chat stream ends (success / fail / cancel).
    func release() {
        retainCount = max(0, retainCount - 1)
        if retainCount == 0 {
            stop()
        }
    }

    var isActive: Bool { retainCount > 0 && player?.isPlaying == true }

    // MARK: - Private

    private func startIfNeeded() {
        guard retainCount > 0 else { return }
        configureSessionIfNeeded()
        if player == nil {
            player = makeSilentPlayer()
        }
        guard let player else { return }
        if !player.isPlaying {
            player.volume = 0.01
            player.numberOfLoops = -1
            player.prepareToPlay()
            _ = player.play()
        }
        installObserversIfNeeded()
        // Hint the system we still need CPU/network.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func stop() {
        player?.stop()
        player = nil
        removeObservers()
        UIApplication.shared.isIdleTimerDisabled = false
        // Leave session active=false so other media can take over cleanly.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        sessionConfigured = false
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else {
            try? AVAudioSession.sharedInstance().setActive(true)
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            // playback + mixWithOthers: keeps us in background without ducking other apps hard.
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            try session.setActive(true)
            sessionConfigured = true
        } catch {
            // Fallback: still try default playback.
            try? session.setCategory(.playback)
            try? session.setActive(true)
            sessionConfigured = true
        }
    }

    private func makeSilentPlayer() -> AVAudioPlayer? {
        // Prefer a tiny generated mono WAV (no asset dependency).
        guard let data = Self.silentWAV(durationSeconds: 2, sampleRate: 8_000) else { return nil }
        do {
            let p = try AVAudioPlayer(data: data)
            p.isMeteringEnabled = false
            p.volume = 0.01
            return p
        } catch {
            return nil
        }
    }

    private func installObserversIfNeeded() {
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] note in
                Task { @MainActor in
                    self?.handleInterruption(note)
                }
            }
        }
        if routeObserver == nil {
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.resumeIfNeeded()
                }
            }
        }
    }

    private func removeObservers() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard retainCount > 0 else { return }
        guard
            let info = note.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            break
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) || true {
                resumeIfNeeded()
            }
        @unknown default:
            resumeIfNeeded()
        }
    }

    private func resumeIfNeeded() {
        guard retainCount > 0 else { return }
        configureSessionIfNeeded()
        if player == nil {
            player = makeSilentPlayer()
        }
        player?.volume = 0.01
        player?.numberOfLoops = -1
        if player?.isPlaying != true {
            _ = player?.play()
        }
    }

    // MARK: - Silent WAV

    /// Minimal PCM WAV (mono, 16-bit) of pure silence.
    private static func silentWAV(durationSeconds: Int, sampleRate: Int) -> Data? {
        let channels = 1
        let bitsPerSample = 16
        let numSamples = sampleRate * max(durationSeconds, 1)
        let dataSize = numSamples * channels * (bitsPerSample / 8)
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func appendASCII(_ s: String) {
            data.append(contentsOf: s.utf8)
        }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        // RIFF header
        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        // fmt chunk
        appendASCII("fmt ")
        appendUInt32(16) // PCM chunk size
        appendUInt16(1) // PCM format
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        appendUInt32(UInt32(byteRate))
        appendUInt16(UInt16(channels * (bitsPerSample / 8)))
        appendUInt16(UInt16(bitsPerSample))
        // data chunk
        appendASCII("data")
        appendUInt32(UInt32(dataSize))
        data.append(Data(count: dataSize)) // zeros = silence
        return data
    }
}
