import SwiftUI

// MARK: - iOS 17 shims for MeloX (upstream targets iOS 26 / Xcode 26)

extension View {
    /// iOS 18 zoom source — no-op on iOS 17 / Xcode 15.
    func matchedTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        self
    }

    /// iOS 18 navigation zoom — no-op.
    func navigationTransition(_ transition: Any) -> some View {
        self
    }

    /// iOS 18 tab bar minimize — no-op.
    func tabBarMinimizeBehavior(_ behavior: Any) -> some View {
        self
    }

    /// iOS 18 tab bottom accessory — no-op (Music uses floating MiniPlayer).
    func tabViewBottomAccessory<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        self
    }
}

// Stub environment for MiniPlayerView.
enum MeloXTabAccessoryPlacement: Equatable {
    case inline
    case expanded
}

private enum MeloXTabAccessoryPlacementKey: EnvironmentKey {
    static let defaultValue: MeloXTabAccessoryPlacement = .expanded
}

extension EnvironmentValues {
    var tabViewBottomAccessoryPlacement: MeloXTabAccessoryPlacement {
        get { self[MeloXTabAccessoryPlacementKey.self] }
        set { self[MeloXTabAccessoryPlacementKey.self] = newValue }
    }
}

// MARK: - Liquid Glass fallbacks (iOS 26)

struct GlassEffectContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        content()
    }
}

struct MeloXGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemFill), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct MeloXGlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(Color.red.gradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == MeloXGlassButtonStyle {
    static var glass: MeloXGlassButtonStyle { MeloXGlassButtonStyle() }
}

extension ButtonStyle where Self == MeloXGlassProminentButtonStyle {
    static var glassProminent: MeloXGlassProminentButtonStyle { MeloXGlassProminentButtonStyle() }
}
