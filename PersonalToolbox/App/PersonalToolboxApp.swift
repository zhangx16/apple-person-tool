import SwiftUI
import SwiftData

@main
struct PersonalToolboxApp: App {
    init() {
        // Warm local tool stores so 服务 → 生活 tools open instantly.
        AnniversaryStore.shared.load()
        QRAssistantStore.shared.load()
        // TranslatorStore needs AppSettings; loaded on first open of 翻译器.
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(AppSettings.shared)
                // App shell owns biometric gate + app-switcher redaction (PR-7).
        }
        .modelContainer(for: [ConversationEntity.self, MessageEntity.self])
    }
}
