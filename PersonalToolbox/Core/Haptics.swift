import UIKit

/// Lightweight haptic helpers. Intentionally sparse — see DESIGN.md §3.8.
/// Meaningful events only: send (light), completion/copy/download (success), failures (error).
/// No feedback for scroll, typing, polling, or chip selection. Honors Reduce Motion.
/// UIKit feedback generators are main-thread only.
@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notifier = UINotificationFeedbackGenerator()

    /// Light impact (e.g. send message, intentional discrete action).
    static func light() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        impact.prepare()
        impact.impactOccurred()
    }

    /// Success notification (stream complete, copy code, download done, probe ok).
    static func success() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        notifier.prepare()
        notifier.notificationOccurred(.success)
    }

    /// Error notification (failed stream, failed probe, failed download action).
    static func error() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        notifier.prepare()
        notifier.notificationOccurred(.error)
    }
}
