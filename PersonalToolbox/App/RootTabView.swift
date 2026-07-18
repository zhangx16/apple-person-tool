import SwiftUI

enum AppTab: Hashable {
    case chat
    case mail
    case download
    case settings
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .chat

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatListView()
                .tabItem {
                    Label("助手", systemImage: "sparkles")
                }
                .tag(AppTab.chat)

            AccountListView()
                .tabItem {
                    Label("邮件", systemImage: "envelope")
                }
                .tag(AppTab.mail)

            DownloadHomeView()
                .tabItem {
                    Label("下载", systemImage: "arrow.down.circle")
                }
                .tag(AppTab.download)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppSettings.shared)
}
