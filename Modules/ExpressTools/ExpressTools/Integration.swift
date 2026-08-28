import SwiftUI

/// ExpressAssistant 的 PersonalToolbox 模块入口。
/// 模块持有自己的数据仓库，通过环境注入给内部页面，不依赖旧快递功能。
struct ExpressAssistantRootView: View {
    var prefill: String? = nil
    @StateObject private var parcelStore = ParcelStore.shared

    var body: some View {
        TabView {
            NavigationStack { DeliveryDashboardView() }
                .tabItem { Label("快递", systemImage: "shippingbox.fill") }
            NavigationStack { LarkChatView() }
                .tabItem { Label("云雀", systemImage: "bird.fill") }
            NavigationStack { ParcelCalendarView() }
                .tabItem { Label("日历", systemImage: "calendar") }
            NavigationStack { ExpressAssistantSettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.orange)
        .environmentObject(parcelStore)
    }
}
