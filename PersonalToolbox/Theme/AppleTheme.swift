import SwiftUI
import UIKit

/// Design System 2.0 — 精致 Apple 风：
/// 材质分层、细腻光影、品牌渐变、弹簧动效。
/// 保留旧 API（appCard / PressableButtonStyle 等）签名兼容，内部视觉全面升级。
/// Respects Reduce Motion / Reduce Transparency (DESIGN §3.7).
enum AppleTheme {
    // MARK: - Radii

    static let cornerRadius: CGFloat = 16
    static let bubbleRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let cardRadius: CGFloat = 20
    static let capsuleRadius: CGFloat = 22

    // MARK: - Press feedback

    static let pressScale: CGFloat = 0.96
    static let pressDuration: Double = 0.1

    // MARK: - Motion

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.15)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.88, blendDuration: 0.1)
    /// Short ease used when Reduce Motion is on.
    static let reduced = Animation.easeOut(duration: 0.2)

    // MARK: - Spacing (8pt grid)

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    static let chatSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 24

    // MARK: - Colors (semantic, auto dark-mode)

    static let accent = Color.accentColor
    static let userBubble = Color.accentColor
    static let assistantBubble = Color(.secondarySystemBackground)
    static let canvas = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let elevated = Color(.tertiarySystemGroupedBackground)

    // MARK: - Motion helpers (DESIGN §3.7)

    static func insertAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : spring
    }

    static func snappyAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : snappy
    }

    static var preferredSpring: Animation {
        UIAccessibility.isReduceMotionEnabled ? reduced : spring
    }

    static var preferredSnappy: Animation {
        UIAccessibility.isReduceMotionEnabled ? reduced : snappy
    }

    static var preferredGentle: Animation {
        UIAccessibility.isReduceMotionEnabled ? reduced : gentle
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

    /// Card entrance: opacity only under Reduce Motion; rise + fade otherwise.
    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 16).combined(with: .scale(scale: 0.97))),
            removal: .opacity
        )
    }

    // MARK: - Typography

    /// Hero 大标题（页面氛围区）
    static let heroFont = Font.system(size: 34, weight: .bold)
    /// 页面级标题
    static let titleFont = Font.system(size: 22, weight: .bold)
    /// 卡片标题 / 强调
    static let headlineFont = Font.system(size: 17, weight: .semibold)
    /// 正文
    static let bodyFont = Font.system(size: 17, weight: .regular)
    /// 辅助说明
    static let subheadlineFont = Font.system(size: 15, weight: .regular)
    /// 元信息
    static let captionFont = Font.system(size: 13, weight: .regular)
    /// 微小标签
    static let microFont = Font.system(size: 11, weight: .medium)
}

// MARK: - Shadow tokens

enum AppShadow {
    /// 近景：轻贴合（小按钮、chip）
    static func near(color: Color = .black) -> some ViewModifier {
        ShadowModifier(color: color.opacity(0.06), radius: 6, y: 2)
    }

    /// 中景：标准卡片
    static func mid(color: Color = .black) -> some ViewModifier {
        ShadowModifier(color: color.opacity(0.08), radius: 16, y: 6)
    }

    /// 远景：悬浮层（搜索栏、composer、分段控件）
    static func far(color: Color = .black) -> some ViewModifier {
        ShadowModifier(color: color.opacity(0.10), radius: 32, y: 12)
    }
}

struct ShadowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        content.shadow(color: color, radius: radius, y: y)
    }
}

// MARK: - Components

/// 统一按压反馈：缩放 + 透明度 + 轻触觉。
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = AppleTheme.pressScale
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(shouldScale(configuration) ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: AppleTheme.pressDuration), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && haptic {
                    Task { @MainActor in Haptics.light() }
                }
            }
    }

    private func shouldScale(_ configuration: Configuration) -> Bool {
        configuration.isPressed && !UIAccessibility.isReduceMotionEnabled
    }
}

/// 语义化别名：与 PressableButtonStyle 相同，新增页面优先用此名。
typealias HapticButtonStyle = PressableButtonStyle

struct GlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var corner: CGFloat = AppleTheme.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(AppleTheme.space4)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(reduceTransparency ? AppleTheme.card : Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
            .modifier(AppShadow.mid())
    }
}

/// 卡片内高光描边：浅色模式下白 0.5，深色模式下自动降为 0.08。
enum AppStroke {
    static var highlight: Color {
        Color.dynamic(
            light: Color.white.opacity(0.5),
            dark: Color.white.opacity(0.12)
        )
    }

    static var subtle: Color {
        Color.dynamic(
            light: Color.white.opacity(0.35),
            dark: Color.white.opacity(0.08)
        )
    }
}

// MARK: - Card modifiers

/// 卡片 V2：材质底 + 内高光描边 + 分层阴影。
struct AppCardV2Modifier: ViewModifier {
    var corner: CGFloat = AppleTheme.cardRadius
    var padding: CGFloat = AppleTheme.space4

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
            .modifier(AppShadow.mid())
    }
}

/// 兼容旧调用：appCard() 内部升级为 V2 视觉，旧页面自动获益。
struct AppCardModifier: ViewModifier {
    var corner: CGFloat = 18
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
            .modifier(AppShadow.mid())
    }
}

extension View {
    func appCard(corner: CGFloat = 18, padding: CGFloat = 14) -> some View {
        modifier(AppCardModifier(corner: corner, padding: padding))
    }

    /// 新卡片样式，新页面优先使用。
    func appCardV2(corner: CGFloat = AppleTheme.cardRadius, padding: CGFloat = AppleTheme.space4) -> some View {
        modifier(AppCardV2Modifier(corner: corner, padding: padding))
    }

    /// 兼容旧调用。
    func appleCard() -> some View {
        modifier(AppCardV2Modifier(corner: AppleTheme.cornerRadius, padding: AppleTheme.space4))
    }
}

// MARK: - Brand gradient

extension Color {
    /// Soft CTA gradient used across live / hub / chat chrome.
    var gradient: LinearGradient {
        brandGradient
    }

    /// 品牌双色渐变（135°），用于图标底板、强调按钮。
    var brandGradient: LinearGradient {
        LinearGradient(
            colors: [self, self.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 柔和氛围渐变（用于背景光晕）。
    var ambientGradient: RadialGradient {
        RadialGradient(
            colors: [self.opacity(0.22), self.opacity(0.05), Color.clear],
            center: .topLeading,
            startRadius: 0,
            endRadius: 320
        )
    }
}

// MARK: - Dynamic color helper

extension UIColor {
    /// 深浅色自动切换的颜色构造。
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

extension Color {
    /// 深浅色自动切换的颜色构造。
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: .dynamic(light: UIColor(light), dark: UIColor(dark)))
    }
}

// MARK: - Shared surfaces

struct AppSurfaceBackground: View {
    var accent: Color = .accentColor

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            // 多层径向光晕模拟 mesh 氛围（iOS 17 无 MeshGradient）
            RadialGradient(
                colors: [accent.opacity(0.10), accent.opacity(0.03), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 380
            )
            RadialGradient(
                colors: [accent.opacity(0.06), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 280
            )
            LinearGradient(
                colors: [Color.clear, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
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
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint.brandGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                    }
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

struct PrimaryButtonLabel: View {
    let title: String
    var systemImage: String?
    var isBusy: Bool = false
    var tint: Color = .accentColor

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
        .background(tint.brandGradient, in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous)
                .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
        }
        .modifier(AppShadow.near())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isBusy ? .updatesFrequently : [])
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                    .frame(width: 96, height: 96)
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(tint.gradient)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .frame(minHeight: 44)
                        .foregroundStyle(.white)
                        .background(tint.brandGradient, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                        }
                        .modifier(AppShadow.near())
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
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            AppleTheme.canvas.opacity(0.98)
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 80, height: 80)
                    Image(systemName: "lock.fill")
                        .font(.title.weight(.medium))
                        .foregroundStyle(Color.accentColor.gradient)
                        .symbolRenderingMode(.hierarchical)
                }
                Text("PersonalToolbox")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
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
            AppSurfaceBackground(accent: Color.accentColor)
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 88, height: 88)
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
                        .frame(width: 88, height: 88)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.accentColor.gradient)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 8) {
                    Text("已锁定")
                        .font(.title2.weight(.bold))
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
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

// MARK: - Staggered entrance

/// 卡片入场交错动画修饰器。尊重 Reduce Motion。
struct StaggeredAppearance: ViewModifier {
    let index: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (reduceMotion ? 0 : 20))
            .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.97))
            .onAppear {
                guard !appeared else { return }
                withAnimation(AppleTheme.preferredSpring.delay(Double(index) * 0.04)) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// 卡片入场交错动画。index 从 0 开始。
    func staggeredAppearance(index: Int) -> some View {
        modifier(StaggeredAppearance(index: index))
    }
}
