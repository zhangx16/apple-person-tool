import UIKit

/// Runtime orientation policy.
/// - iPhone chrome: portrait; live/video fullscreen may lock landscape.
/// - iPad: free rotation by default (all orientations); fullscreen still prefers landscape.
enum OrientationHelper {
    /// Current allowed orientations (read by `AppDelegate`).
    /// `nonisolated(unsafe)` so UIKit orientation callbacks can read it without hopping actors.
    nonisolated(unsafe) private(set) static var mask: UIInterfaceOrientationMask = OrientationHelper.defaultMask

    /// Device-appropriate chrome orientations.
    nonisolated static var defaultMask: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    nonisolated static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Prefer landscape for live / video fullscreen.
    @MainActor
    static func lockLandscape() {
        mask = .landscape
        apply(preferred: .landscapeRight)
    }

    /// Restore app-chrome orientations after leaving fullscreen.
    /// On iPhone this is portrait; on iPad all orientations (no forced spin).
    @MainActor
    static func lockPortrait() {
        restoreDefault()
    }

    /// Explicit restore to device default (same as `lockPortrait`, clearer call site).
    @MainActor
    static func restoreDefault() {
        mask = defaultMask
        if isPad {
            // Update allowed mask only — don't yank the user into portrait.
            return
        }
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
