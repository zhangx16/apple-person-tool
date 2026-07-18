import SwiftUI

/// Visual system inspired by Apple Design (WWDC fluid interfaces):
/// instant press feedback, spring motion, materials, restraint, system typography.
enum AppleTheme {
    static let cornerRadius: CGFloat = 16
    static let bubbleRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
    static let pressScale: CGFloat = 0.97
    static let pressDuration: Double = 0.1

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.15)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.9)

    static let accent = Color.accentColor
    static let userBubble = Color.accentColor
    static let assistantBubble = Color(.secondarySystemBackground)
    static let canvas = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)

    static let chatSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 20
}

// MARK: - Components

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = AppleTheme.pressScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: AppleTheme.pressDuration), value: configuration.isPressed)
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
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
        .padding(.vertical, 14)
        .foregroundStyle(.white)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous))
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 4)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    func appleCard() -> some View {
        self
            .padding(16)
            .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }
}
