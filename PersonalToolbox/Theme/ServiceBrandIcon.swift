import SwiftUI
import UIKit

/// Brand icons for self-hosted projects shown in hub / settings / headers.
enum ServiceBrand: String, CaseIterable, Identifiable {
    case sublink
    case komari
    case youtube
    case sub2
    case chat
    case settings

    var id: String { rawValue }

    /// Asset catalog name when a custom brand image exists.
    var assetName: String? {
        switch self {
        case .sublink: return "IconSublink"
        case .komari: return "IconKomari"
        case .youtube: return "IconYouTube"
        case .sub2: return "IconSub2"
        case .chat, .settings: return nil
        }
    }

    /// SF Symbol fallback (and for tab bars that need template glyphs).
    var systemImage: String {
        switch self {
        case .sublink: return "link.circle.fill"
        case .komari: return "server.rack"
        case .youtube: return "play.rectangle.fill"
        case .sub2: return "chart.bar.fill"
        case .chat: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .sublink: return "SublinkX"
        case .komari: return "Komari"
        case .youtube: return "视频下载"
        case .sub2: return "Sub2API"
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
