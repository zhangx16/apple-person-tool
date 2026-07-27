import SwiftUI

@main
struct PersonalToolboxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Warm local tool stores so 服务 → 生活 tools open instantly. Deferred to
        // right after launch (instead of running synchronously here) so the
        // first frame isn't blocked on disk I/O.
        Task { @MainActor in
            AnniversaryStore.shared.load()
            QRAssistantStore.shared.load()
        }
        LocalNotifier.installForegroundDelegate()
        // iPhone chrome is portrait-first; iPad allows free rotation.
        // Live / video fullscreen temporarily locks landscape on both.
        OrientationHelper.restoreDefault()
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
