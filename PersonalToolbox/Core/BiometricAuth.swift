import Foundation
import LocalAuthentication

/// Optional app-lock helper (K12). Prefer device owner auth so passcode works
/// when biometrics are unavailable or not enrolled.
enum BiometricAuth {
    /// Evaluate device owner authentication (Face ID / Touch ID / passcode).
    /// Returns `true` on success. Runs the system UI off the MainActor callback.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var error: NSError?
        // Prefer full device-owner policy (biometrics + passcode fallback).
        let policy: LAPolicy
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            policy = .deviceOwnerAuthentication
        } else if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else {
            // No auth method available (e.g. simulator without passcode) — fail closed.
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Whether the device can present biometric or passcode UI.
    static var canAuthenticate: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            || context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}
