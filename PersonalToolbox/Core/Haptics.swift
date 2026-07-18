import UIKit

/// Lightweight haptic helpers. Intentionally sparse — see DESIGN.md §3.8.
enum Haptics {
    /// Light impact (e.g. send message).
    static func light() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Success notification (e.g. stream complete, copy code, download done).
    static func success() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Error notification.
    static func error() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
