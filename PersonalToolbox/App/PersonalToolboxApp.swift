import SwiftUI

@main
struct PersonalToolboxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Warm local tool stores so 服务 → 生活 tools open instantly.
        AnniversaryStore.shared.load()
        QRAssistantStore.shared.load()
        LocalNotifier.installForegroundDelegate()
        // App chrome is portrait-first; live fullscreen temporarily locks landscape.
        OrientationHelper.lockPortrait()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(AppSettings.shared)
                .environmentObject(ShareInbox.shared)
                .onOpenURL { url in
                    ShareInbox.shared.handle(url: url)
                }
        }
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
