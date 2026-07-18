import SwiftUI

/// Bottom「监控」tab shell: switch Sub2 管理 / Cloudflare via the nav title menu.
struct MonitorShellView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var project: MonitorProject = .sub2

    var body: some View {
        Group {
            switch project {
            case .sub2:
                MonitorHomeView(hidesChromeTitle: true)
            case .cloudflare:
                CloudflareHomeView(hidesChromeTitle: true)
            }
        }
        // Reset navigation path (e.g. CF zone detail) when switching projects.
        .id(project)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SelectableNavTitle(
                    options: Array(MonitorProject.allCases),
                    selection: $project,
                    title: { $0.title },
                    brand: { $0.brand },
                    accessibilityHint: "点按切换监控项目"
                )
            }
        }
        .onAppear {
            syncFromSettings()
        }
        .onChange(of: settings.monitorProjectRaw) { _, _ in
            syncFromSettings()
        }
        .onChange(of: project) { _, newValue in
            settings.monitorProjectRaw = newValue.rawValue
        }
    }

    private func syncFromSettings() {
        if let p = MonitorProject(rawValue: settings.monitorProjectRaw), p != project {
            project = p
        }
    }
}
