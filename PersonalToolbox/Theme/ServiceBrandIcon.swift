import SwiftUI
import UIKit

/// Brand icons for self-hosted projects + local tools (hub / settings / headers).
enum ServiceBrand: String, CaseIterable, Identifiable {
    case sublink
    case komari
    case youtube
    case douyin
    case bilibili
    case sub2
    case anniversary
    case qrAssistant
    case translator
    case cloudflare
    case clsNews
    case ipCheck
    case chat
    case settings
    // Local tools / hub entries without custom assets — colored SF glyphs
    case quickActions
    case clipboard
    case password
    case habits
    case express
    case market
    case rss
    case health
    case live

    var id: String { rawValue }

    /// Asset catalog name when a custom brand image exists.
    var assetName: String? {
        switch self {
        case .sublink: return "IconSublink"
        case .komari: return "IconKomari"
        case .youtube: return "IconYouTube"
        case .douyin: return "IconDouyin"
        case .bilibili: return "IconLiveBilibili"
        case .sub2: return "IconSub2"
        case .anniversary: return "IconAnniversary"
        case .qrAssistant: return "IconQRAssistant"
        case .translator: return "IconTranslator"
        case .cloudflare: return "IconCloudflare"
        case .clsNews: return "IconCLS"
        case .ipCheck: return "IconIPCheck"
        default: return nil
        }
    }

    /// SF Symbol (fallback or primary for tools).
    var systemImage: String {
        switch self {
        case .sublink: return "link.circle.fill"
        case .komari: return "server.rack"
        case .youtube: return "play.rectangle.fill"
        case .douyin: return "music.note.tv.fill"
        case .bilibili: return "play.rectangle.on.rectangle.fill"
        case .sub2: return "chart.bar.fill"
        case .anniversary: return "heart.text.square.fill"
        case .qrAssistant: return "qrcode.viewfinder"
        case .translator: return "translate"
        case .cloudflare: return "bolt.fill"
        case .clsNews: return "newspaper.fill"
        case .ipCheck: return "antenna.radiowaves.left.and.right"
        case .chat: return "sparkles"
        case .settings: return "gearshape.fill"
        case .quickActions: return "bolt.horizontal.circle.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .password: return "key.fill"
        case .habits: return "checklist"
        case .express: return "shippingbox.fill"
        case .market: return "chart.line.uptrend.xyaxis"
        case .rss: return "dot.radiowaves.up.forward"
        case .health: return "heart.text.square.fill"
        case .live: return "play.tv.fill"
        }
    }

    /// Brand / accent color for SF glyph + soft plate.
    var tint: Color {
        switch self {
        case .sublink: return Color(hex: 0x0A84FF)
        case .komari: return Color(hex: 0x30D158)
        case .youtube: return Color(hex: 0xFF3B30)
        case .douyin: return Color(hex: 0xFF2D55)
        case .bilibili: return Color(hex: 0x00A1D6)
        case .sub2: return Color(hex: 0x5E5CE6)
        case .anniversary: return Color(hex: 0xFF2D55)
        case .qrAssistant: return Color(hex: 0x64D2FF)
        case .translator: return Color(hex: 0xBF5AF2)
        case .cloudflare: return Color(hex: 0xF6821F)
        case .clsNews: return Color(hex: 0xFF9F0A)
        case .ipCheck: return Color(hex: 0xAE6DD8)
        case .chat: return Color(hex: 0x0A84FF)
        case .settings: return Color(hex: 0x8E8E93)
        case .quickActions: return Color(hex: 0xFF9F0A)
        case .clipboard: return Color(hex: 0x0A84FF)
        case .password: return Color(hex: 0xBF5AF2)
        case .habits: return Color(hex: 0x30D158)
        case .express: return Color(hex: 0xAC8E68)
        case .market: return Color(hex: 0x34C759)
        case .rss: return Color(hex: 0xFF9500)
        case .health: return Color(hex: 0xFF375F)
        case .live: return Color(hex: 0xFF375F)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .sublink: return "SublinkX"
        case .komari: return "Komari"
        case .youtube: return "YouTube 下载"
        case .douyin: return "抖音下载"
        case .bilibili: return "B站下载"
        case .sub2: return "Sub2API"
        case .anniversary: return "纪念日"
        case .qrAssistant: return "二维码助手"
        case .translator: return "翻译器"
        case .cloudflare: return "Cloudflare"
        case .clsNews: return "财联社电报"
        case .ipCheck: return "IP 检测"
        case .chat: return "助手"
        case .settings: return "设置"
        case .quickActions: return "快捷动作"
        case .clipboard: return "剪贴板"
        case .password: return "密码生成器"
        case .habits: return "习惯与待办"
        case .express: return "快递查询"
        case .market: return "行情"
        case .rss: return "RSS"
        case .health: return "服务健康"
        case .live: return "直播"
        }
    }
}

/// Rounded brand badge used in lists and section headers.
struct ServiceBrandIcon: View {
    let brand: ServiceBrand
    var size: CGFloat = 36
    var cornerRadius: CGFloat? = nil
    /// Draw a soft tinted plate (or neutral when using custom asset).
    var showsBackground: Bool = true

    private var radius: CGFloat {
        cornerRadius ?? size * 0.22
    }

    private var hasAsset: Bool {
        if let asset = brand.assetName, UIImage(named: asset) != nil { return true }
        return false
    }

    var body: some View {
        ZStack {
            if showsBackground {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(hasAsset
                          ? Color(.secondarySystemBackground)
                          : brand.tint.brandGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                    }
            }
            Group {
                if let asset = brand.assetName, UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.12)
                } else {
                    Image(systemName: brand.systemImage)
                        .font(.system(size: size * 0.44, weight: .semibold))
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

/// Compact leading brand mark for navigation / section titles.
struct ServiceBrandTitle: View {
    let brand: ServiceBrand
    let title: String
    var iconSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            ServiceBrandIcon(brand: brand, size: iconSize, showsBackground: true)
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(brand.accessibilityLabel) \(title)")
    }
}
