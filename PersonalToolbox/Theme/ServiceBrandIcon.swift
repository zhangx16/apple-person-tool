import SwiftUI
import UIKit

/// Brand icons for self-hosted projects shown in hub / settings / headers.
enum ServiceBrand: String, CaseIterable, Identifiable {
    case sublink
    case komari
    case youtube
    case douyin
    case sub2
    case anniversary
    case qrAssistant
    case translator
    case cloudflare
    case clsNews
    case ipCheck
    case chat
    case settings

    var id: String { rawValue }

    /// Asset catalog name when a custom brand image exists.
    var assetName: String? {
        switch self {
        case .sublink: return "IconSublink"
        case .komari: return "IconKomari"
        case .youtube: return "IconYouTube"
        case .douyin: return "IconDouyin"
        case .sub2: return "IconSub2"
        case .anniversary: return "IconAnniversary"
        case .qrAssistant: return "IconQRAssistant"
        case .translator: return "IconTranslator"
        case .cloudflare: return "IconCloudflare"
        case .clsNews: return "IconCLS"
        case .ipCheck: return "IconIPCheck"
        case .chat, .settings: return nil
        }
    }

    /// SF Symbol fallback (and for tab bars that need template glyphs).
    var systemImage: String {
        switch self {
        case .sublink: return "link.circle.fill"
        case .komari: return "server.rack"
        case .youtube: return "play.rectangle.fill"
        case .douyin: return "music.note.tv.fill"
        case .sub2: return "chart.bar.fill"
        case .anniversary: return "heart.text.square.fill"
        case .qrAssistant: return "qrcode.viewfinder"
        case .translator: return "translate"
        case .cloudflare: return "bolt.fill"
        case .clsNews: return "newspaper.fill"
        case .ipCheck: return "antenna.radiowaves.left.and.right"
        case .chat: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .sublink: return "SublinkX"
        case .komari: return "Komari"
        case .youtube: return "YouTube 下载"
        case .douyin: return "抖音下载"
        case .sub2: return "Sub2API"
        case .anniversary: return "纪念日"
        case .qrAssistant: return "二维码助手"
        case .translator: return "翻译器"
        case .cloudflare: return "Cloudflare"
        case .clsNews: return "财联社电报"
        case .ipCheck: return "IP 检测"
        case .chat: return "助手"
        case .settings: return "设置"
        }
    }
}

/// Rounded brand badge used in lists and section headers.
struct ServiceBrandIcon: View {
    let brand: ServiceBrand
    var size: CGFloat = 36
    var cornerRadius: CGFloat? = nil
    /// Draw a subtle plate behind transparent logos.
    var showsBackground: Bool = true

    private var radius: CGFloat {
        cornerRadius ?? size * 0.22
    }

    var body: some View {
        ZStack {
            if showsBackground {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            }
            Group {
                if let asset = brand.assetName, UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.12)
                } else {
                    Image(systemName: brand.systemImage)
                        .font(.system(size: size * 0.48, weight: .semibold))
                        .foregroundStyle(.secondary)
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
