import SwiftUI

@main
struct ExpressToolsApp: App {
    @StateObject private var store = ParcelStore.shared

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { DeliveryDashboardView() }
                .tabItem { Label("快递", systemImage: "shippingbox.fill") }
            NavigationStack { LarkChatView() }
                .tabItem { Label("云雀", systemImage: "bird.fill") }
            NavigationStack { ParcelCalendarView() }
                .tabItem { Label("日历", systemImage: "calendar") }
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.orange)
    }
}
