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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .douyin: return "抖音"
        }
    }

    var brand: ServiceBrand {
        switch self {
        case .youtube: return .youtube
        case .douyin: return .youtube // no dedicated icon; reuse media glyph via system fallback path
        }
    }

    /// Prefer SF Symbol when no dedicated brand asset for Douyin.
    var systemImage: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .douyin: return "music.note.tv.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .youtube: return "YouTube 下载"
        case .douyin: return "抖音下载"
        }
    }
}

/// Download principal title with optional custom icon for Douyin.
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
                        Label(option.title, systemImage: option.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if selection == .youtube {
                    ServiceBrandTitle(brand: .youtube, title: selection.title, iconSize: 20)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: selection.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Text(selection.title)
                            .font(.headline)
                    }
                }
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
