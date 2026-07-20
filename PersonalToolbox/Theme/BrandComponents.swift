import SwiftUI
import UIKit

// MARK: - BrandIconBadge

/// 渐变底板 + 白色 SF Symbol 的品牌图标升级版。
/// 用于 Hero 区域、功能卡片、强调入口。
struct BrandIconBadge: View {
    let brand: ServiceBrand
    var size: CGFloat = 44
    var showsBackground: Bool = true

    private var radius: CGFloat {
        size * 0.26
    }

    private var hasAsset: Bool {
        if let asset = brand.assetName, UIImage(named: asset) != nil { return true }
        return false
    }

    var body: some View {
        ZStack {
            if showsBackground {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(hasAsset ? Color(.secondarySystemBackground) : brand.tint.brandGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                    }
                    .modifier(AppShadow.near())
            }
            Group {
                if let asset = brand.assetName, UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.14)
                } else {
                    Image(systemName: brand.systemImage)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - FloatingCapsuleBar

/// ultraThinMaterial 悬浮胶囊容器，用于搜索栏、分段切换等浮层。
struct FloatingCapsuleBar<Content: View>: View {
    var cornerRadius: CGFloat = AppleTheme.capsuleRadius
    var padding: CGFloat = 4
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule()
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
            .modifier(AppShadow.far())
    }
}

// MARK: - HeroHeader

/// 页面顶部品牌氛围区：品牌色光晕 + 大标题 + 可选副标题/操作。
/// 注入品牌个性，替代千篇一律的 navigationTitle。
struct HeroHeader<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    var brand: ServiceBrand? = nil
    var accent: Color = .accentColor
    var systemImage: String? = nil
    @ViewBuilder var actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        brand: ServiceBrand? = nil,
        accent: Color = .accentColor,
        systemImage: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.brand = brand
        self.accent = accent
        self.systemImage = systemImage
        self.actions = actions()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 品牌氛围光晕
            RadialGradient(
                colors: [accent.opacity(0.16), accent.opacity(0.04), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 320
            )
            .frame(height: 180)
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: AppleTheme.space4) {
                HStack(alignment: .center, spacing: AppleTheme.space4) {
                    if let brand {
                        BrandIconBadge(brand: brand, size: 52)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(accent.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                            }
                            .modifier(AppShadow.near())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(AppleTheme.heroFont)
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(AppleTheme.subheadlineFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                actions
            }
            .padding(.horizontal, AppleTheme.space4)
            .padding(.top, AppleTheme.space2)
            .padding(.bottom, AppleTheme.space4)
        }
    }
}

extension HeroHeader where Actions == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        brand: ServiceBrand? = nil,
        accent: Color = .accentColor,
        systemImage: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.brand = brand
        self.accent = accent
        self.systemImage = systemImage
        self.actions = EmptyView()
    }
}

// MARK: - LiveBadge

/// 呼吸动画 LIVE 角标。Reduce Motion 下静态显示。
struct LiveBadge: View {
    var isLive: Bool = true
    var size: Size = .medium

    enum Size {
        case small, medium, large

        var font: Font {
            switch self {
            case .small: return .system(size: 9, weight: .heavy)
            case .medium: return .system(size: 11, weight: .heavy)
            case .large: return .system(size: 13, weight: .heavy)
            }
        }

        var hPadding: CGFloat {
            switch self {
            case .small: return 5
            case .medium: return 7
            case .large: return 9
            }
        }

        var vPadding: CGFloat {
            switch self {
            case .small: return 2
            case .medium: return 3
            case .large: return 4
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Text("LIVE")
            .font(size.font)
            .foregroundStyle(.white)
            .padding(.horizontal, size.hPadding)
            .padding(.vertical, size.vPadding)
            .background {
                Capsule()
                    .fill(isLive ? Color.red : Color.gray)
            }
            .overlay {
                Capsule()
                    .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
            }
            .scaleEffect(isPulsing ? 1.08 : 1.0)
            .opacity(isPulsing ? 0.85 : 1.0)
            .onAppear {
                guard isLive, !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
            .accessibilityLabel(isLive ? "直播中" : "未开播")
    }
}

// MARK: - StatusPill

/// 彩色状态徽标，用于配置状态、在线状态、风险等级等。
struct StatusPill: View {
    let title: String
    var color: Color = .secondary
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(color.opacity(0.24), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - SectionDivider

/// 带标题的分割线，用于卡片内部分区。
struct SectionDivider: View {
    let title: String?
    var systemImage: String? = nil

    init(_ title: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: AppleTheme.space2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, AppleTheme.space2)
    }
}

// MARK: - GridCard

/// 2 列网格品牌卡片，用于服务 Hub 等场景。
struct GridCard<Content: View>: View {
    var cornerRadius: CGFloat = AppleTheme.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppleTheme.space4)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
            .modifier(AppShadow.mid())
    }
}

// MARK: - FloatingSearchBar

/// 悬浮搜索胶囊，带图标、清除按钮和可选右侧操作。
struct FloatingSearchBar<Trailing: View>: View {
    @Binding var text: String
    var placeholder: String = "搜索"
    var onSubmit: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body.weight(.medium))
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .strokeBorder(AppStroke.highlight, lineWidth: 1)
        }
        .modifier(AppShadow.far())
    }
}

extension FloatingSearchBar where Trailing == EmptyView {
    init(text: Binding<String>, placeholder: String = "搜索", onSubmit: @escaping () -> Void = {}) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.trailing = EmptyView()
    }
}
