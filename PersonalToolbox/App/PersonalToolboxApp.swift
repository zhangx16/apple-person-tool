import SwiftUI
import SwiftData

@main
struct PersonalToolboxApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(AppSettings.shared)
        }
        .modelContainer(for: [ConversationEntity.self, MessageEntity.self])
    }
}
