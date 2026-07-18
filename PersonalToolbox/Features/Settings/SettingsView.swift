import SwiftUI

/// Placeholder shell for the 设置 tab. Credentials & probes arrive in a later PR.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "gearshape",
                title: "设置",
                message: "服务凭证、外观与隐私选项将在后续版本接入。"
            )
            .background(AppleTheme.canvas)
            .navigationTitle("设置")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
