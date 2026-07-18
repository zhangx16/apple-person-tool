import SwiftUI

@main
struct PersonalToolboxApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(AppSettings.shared)
        }
        // SwiftData modelContainer is wired in a later PR once entities exist.
    }
}
