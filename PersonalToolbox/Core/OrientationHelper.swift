import UIKit

/// Runtime orientation lock for fullscreen live player.
/// App chrome defaults to portrait; fullscreen live forces landscape.
enum OrientationHelper {
    /// Current allowed orientations (read by `AppDelegate`).
    /// `nonisolated(unsafe)` so UIKit orientation callbacks can read it without hopping actors.
    nonisolated(unsafe) private(set) static var mask: UIInterfaceOrientationMask = .portrait

    /// Prefer landscape for live fullscreen.
    @MainActor
    static func lockLandscape() {
        mask = .landscape
        apply(preferred: .landscapeRight)
    }

    /// Restore portrait after leaving fullscreen.
    @MainActor
    static func lockPortrait() {
        mask = .portrait
        apply(preferred: .portrait)
    }

    @MainActor
    private static func apply(preferred: UIInterfaceOrientation) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        if #available(iOS 16.0, *) {
            let orientations: UIInterfaceOrientationMask =
                (preferred == .landscapeLeft || preferred == .landscapeRight) ? .landscape : .portrait
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
        }

        // Best-effort force rotation after the allowed mask is updated.
        UIDevice.current.setValue(preferred.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

/// Provides dynamic orientation mask to UIKit.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationHelper.mask
    }
}
