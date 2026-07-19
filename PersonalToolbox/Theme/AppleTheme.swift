import SwiftUI
import UIKit

/// Visual system inspired by Apple Design (WWDC fluid interfaces):
/// instant press feedback, spring motion, materials, restraint, system typography.
/// Respects Reduce Motion: prefer opacity/crossfade over large springs (DESIGN §3.7).
enum AppleTheme {
    static let cornerRadius: CGFloat = 16
    static let bubbleRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
    static let pressScale: CGFloat = 0.97
    static let pressDuration: Double = 0.1

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.15)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.9)
    /// Short ease used when Reduce Motion is on.
    static let reduced = Animation.easeOut(duration: 0.2)

    static let accent = Color.accentColor
    static let userBubble = Color.accentColor
    static let assistantBubble = Color(.secondarySystemBackground)
    static let canvas = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)

    static let chatSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 20

    // MARK: - Motion helpers (DESIGN §3.7)

    /// Insert / list change animation: spring, or easeOut when reduced.
    static func insertAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : spring
    }

    /// Snappy UI transitions (scroll-to-bottom, toggles).
    static func snappyAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : snappy
    }

    /// Convenience using the system accessibility flag (ViewModels / non-View).
    static var preferredSpring: Animation {
        UIAccessibility.isReduceMotionEnabled ? reduced : spring
    }

    static var preferredSnappy: Animation {
        UIAccessibility.isReduceMotionEnabled ? reduced : snappy
    }

    /// Bubble insertion: opacity only under Reduce Motion; slight rise otherwise.
    static func bubbleTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        )
    }
}

// MARK: - Components

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = AppleTheme.pressScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(shouldScale(configuration) ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: AppleTheme.pressDuration), value: configuration.isPressed)
    }

    private func shouldScale(_ configuration: Configuration) -> Bool {
        configuration.isPressed && !UIAccessibility.isReduceMotionEnabled
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous)
                        .fill(AppleTheme.card)
                } else {
                    RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
    }
}

struct PrimaryButtonLabel: View {
    let title: String
    var systemImage: String?
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isBusy ? .updatesFrequently : [])
    }
}

// MARK: - Global modern surfaces (shared by 助手 / 直播 / 服务 / 设置)

struct AppSurfaceBackground: View {
    var accent: Color = .accentColor

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [accent.opacity(0.07), Color.clear, Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

struct AppCardModifier: ViewModifier {
    var corner: CGFloat = 18
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            }
    }
}

extension View {
    func appCard(corner: CGFloat = 18, padding: CGFloat = 14) -> some View {
        modifier(AppCardModifier(corner: corner, padding: padding))
    }
}

extension Color {
    /// Soft CTA gradient used across live / hub / chat chrome.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [self, self.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AppSectionTitle: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .textCase(nil)
    }
}

struct AppNavRow: View {
    let title: String
    let subtitle: String
    var brand: ServiceBrand? = nil
    var systemImage: String? = nil
    var tint: Color = Color(hex: 0x0A84FF)

    var body: some View {
        HStack(spacing: 14) {
            if let brand {
                ServiceBrandIcon(brand: brand, size: 44)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(subtitle)")
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 4)
                .accessibilityLabel(actionTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(EmptyStateAccessibility(
            title: title,
            message: message,
            hasAction: actionTitle != nil
        ))
    }
}

/// Keeps empty-state VO simple: combined label when no CTA; container when a button is present.
private struct EmptyStateAccessibility: ViewModifier {
    let title: String
    let message: String
    let hasAction: Bool

    func body(content: Content) -> some View {
        if hasAction {
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title)。\(message)")
        }
    }
}

/// Full-screen cover used when `hideSensitiveInAppSwitcher` and app resigns active.
/// Opaque base so chat/mail text is not legible in the app-switcher snapshot
/// (`.ultraThinMaterial` alone is too translucent — review Issue 1).
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            // Solid fill first — material alone can leave content readable.
            Color(.systemBackground)
            AppleTheme.canvas.opacity(0.98)
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                Text("PersonalToolbox")
                    .font(.headline)
            }
            .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Full-screen Face ID / Touch ID / passcode gate when `requireBiometricUnlock`.
struct BiometricLockView: View {
    var onUnlocked: () -> Void

    @State private var statusMessage = "需要验证身份"
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            AppleTheme.canvas.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.largeTitle.weight(.light))
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text("已锁定")
                    .font(.title2.weight(.semibold))
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    Task { await authenticate() }
                } label: {
                    PrimaryButtonLabel(
                        title: isAuthenticating ? "验证中…" : "使用面容或触控 ID 解锁",
                        systemImage: "faceid",
                        isBusy: isAuthenticating
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isAuthenticating)
                .padding(.horizontal, 40)
                .accessibilityHint("验证设备所有者身份后进入应用")
            }
        }
        .accessibilityElement(children: .contain)
        .task {
            await authenticate()
        }
    }

    @MainActor
    private func authenticate() async {
        guard !isAuthenticating else { return }
        // No enrolled biometrics/passcode — cannot complete unlock UI.
        // Enabling the setting requires a successful preflight in Settings.
        guard BiometricAuth.canAuthenticate else {
            statusMessage = "此设备未设置面容 ID、触控 ID 或设备密码，无法验证。请在系统设置中配置后再试。"
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ok = await BiometricAuth.authenticate(reason: "解锁 PersonalToolbox 以继续使用")
        if ok {
            statusMessage = "已解锁"
            onUnlocked()
        } else {
            statusMessage = "验证失败或已取消，请重试"
            Haptics.error()
        }
    }
}

extension View {
    func appleCard() -> some View {
        self
            .padding(16)
            .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }
}
