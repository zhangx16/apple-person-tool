import SwiftUI

// MARK: - MeloX embedding shims
// Deployment target is iOS 18+. Prefer system APIs when present; provide
// fallbacks for APIs that only exist on iOS 26 / Xcode 26 (Glass, WebPage).

// Toolbar shared background (iOS 26 / newer toolbars)
extension ToolbarContent {
    @ToolbarContentBuilder
    func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent {
        self
    }
}

extension View {
    /// Fallback overload for call sites that pass `.visible` without type context.
    func sharedBackgroundVisibility(_ visibility: Any) -> some View { self }

    func sliderThumbVisibility(_ visibility: Any) -> some View { self }
}

// Liquid Glass (iOS 26) — no-op container + button styles on older SDKs
struct GlassEffectContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View { content() }
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

// MiniPlayer placement env (iOS 18 tab accessory)
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
