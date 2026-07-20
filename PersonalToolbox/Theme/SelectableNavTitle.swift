import SwiftUI

/// Tappable navigation principal that opens a menu to switch the active project/mode.
struct SelectableNavTitle<Option: Hashable & Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let brand: (Option) -> ServiceBrand
    var accessibilityHint: String = "点按切换项目"

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option
                    Haptics.light()
                } label: {
                    if option == selection {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                ServiceBrandTitle(brand: brand(selection), title: title(selection), iconSize: 20)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title(selection))
        .accessibilityHint(accessibilityHint)
    }
}

// MARK: - Tab project enums

enum MonitorProject: String, CaseIterable, Identifiable, Hashable {
    case sub2
    case cloudflare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sub2: return "Sub2 管理"
        case .cloudflare: return "Cloudflare"
        }
    }

    var brand: ServiceBrand {
        switch self {
        case .sub2: return .sub2
        case .cloudflare: return .cloudflare
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .sub2: return "Sub2API 监控"
        case .cloudflare: return "Cloudflare 监控"
        }
    }
}

enum DownloadProject: String, CaseIterable, Identifiable, Hashable {
    case youtube
    case douyin
    case bilibili

    var id: String { rawValue }

    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .douyin: return "抖音"
        case .bilibili: return "B站"
        }
    }

    var brand: ServiceBrand {
        switch self {
        case .youtube: return .youtube
        case .douyin: return .douyin
        case .bilibili: return .bilibili
        }
    }

    var systemImage: String {
        brand.systemImage
    }

    var accessibilityLabel: String {
        brand.accessibilityLabel
    }

    /// Local on-device download (no yt-dlp server).
    var isLocal: Bool {
        switch self {
        case .douyin, .bilibili: return true
        case .youtube: return false
        }
    }
}

/// Download principal title: brand icon + name + switch chevron.
struct DownloadNavTitle: View {
    @Binding var selection: DownloadProject

    var body: some View {
        Menu {
            ForEach(DownloadProject.allCases) { option in
                Button {
                    selection = option
                    Haptics.light()
                } label: {
                    if option == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                ServiceBrandTitle(brand: selection.brand, title: selection.title, iconSize: 20)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(selection.accessibilityLabel)
        .accessibilityHint("点按切换下载项目")
    }
}
