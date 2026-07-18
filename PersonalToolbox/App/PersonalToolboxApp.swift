import SwiftUI
import SwiftData

@main
struct PersonalToolboxApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(AppSettings.shared)
                // App shell owns biometric gate + app-switcher redaction (PR-7).
        }
        .modelContainer(for: [ConversationEntity.self, MessageEntity.self])
    }
}
