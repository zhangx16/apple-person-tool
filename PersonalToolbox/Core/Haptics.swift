import UIKit

/// Lightweight haptic helpers. Intentionally sparse — see DESIGN.md §3.8.
/// UIKit feedback generators are main-thread only.
@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notifier = UINotificationFeedbackGenerator()

    /// Light impact (e.g. send message).
    static func light() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        impact.prepare()
        impact.impactOccurred()
    }

    /// Success notification (e.g. stream complete, copy code, download done).
    static func success() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        notifier.prepare()
        notifier.notificationOccurred(.success)
    }

    /// Error notification.
    static func error() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        notifier.prepare()
        notifier.notificationOccurred(.error)
    }
}
