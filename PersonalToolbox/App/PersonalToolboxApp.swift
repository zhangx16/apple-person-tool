import SwiftUI
import SwiftData

@main
struct PersonalToolboxApp: App {
    init() {
        // Warm local tool stores so 服务 → 生活 tools open instantly.
        AnniversaryStore.shared.load()
        QRAssistantStore.shared.load()
        // TranslatorStore needs AppSettings; loaded on first open of 翻译器.
        LocalNotifier.installForegroundDelegate()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(AppSettings.shared)
                .environmentObject(ShareInbox.shared)
                .onOpenURL { url in
                    ShareInbox.shared.handle(url: url)
                }
                // App shell owns biometric gate + app-switcher redaction (PR-7).
        }
        .modelContainer(for: [ConversationEntity.self, MessageEntity.self])
    }
}

/// Receives Share Extension handoff and surfaces a sheet in the host UI.
@MainActor
final class ShareInbox: ObservableObject {
    static let shared = ShareInbox()

    @Published var pendingPayload: ShareHandoffPayload?
    @Published var showSheet = false

    func handle(url: URL) {
        guard ShareHandoff.isShareURL(url) else { return }
        if let payload = ShareHandoff.consume() {
            pendingPayload = payload
            showSheet = true
            // Also stash text into clipboard history
            let text = payload.combinedText
            if !text.isEmpty {
                ClipboardStore.shared.addManual(text)
            }
        }
    }

    func consumeOnLaunch() {
        if let payload = ShareHandoff.consume() {
            pendingPayload = payload
            showSheet = true
            let text = payload.combinedText
            if !text.isEmpty {
                ClipboardStore.shared.addManual(text)
            }
        }
    }
}
