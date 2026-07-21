import AppIntents
import Foundation

// MARK: - App Intents (Shortcuts)

@available(iOS 16.0, *)
struct OpenOverviewIntent: AppIntent {
    static var title: LocalizedStringResource = "打开总览"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 16.0, *)
struct OpenCheckinIntent: AppIntent {
    static var title: LocalizedStringResource = "打开签到中心"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 16.0, *)
struct CaptureClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "捕获剪贴板"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        if let item = ClipboardStore.shared.capturePasteboard() {
            return .result(value: item.preview)
        }
        return .result(value: "剪贴板为空或与上一条相同")
    }
}

@available(iOS 16.0, *)
struct RefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新服务状态"

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await ServiceHealthService.shared.probeAll()
        let summary = await MainActor.run { () -> String in
            let fails = ServiceHealthService.shared.items.filter { $0.status == .fail }.count
            let due = SubscriptionStore.shared.dueSoon.count
            ActivityEventStore.shared.log(.make(
                title: "快捷指令刷新",
                subtitle: fails == 0 ? "服务探测完成" : "\(fails) 项异常",
                systemImage: "arrow.triangle.2.circlepath",
                tintHex: fails == 0 ? 0x30D158 : 0xFF453A,
                route: "health"
            ))
            return fails == 0 ? "服务正常" : "\(fails) 项异常"
        }
        return .result(value: summary)
    }
}

@available(iOS 16.0, *)
struct ToolboxAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenOverviewIntent(),
            phrases: [
                "打开 \(.applicationName) 总览",
                "打开总览 \(.applicationName)"
            ],
            shortTitle: "总览",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: OpenCheckinIntent(),
            phrases: [
                "打开 \(.applicationName) 签到",
                "查看签到 \(.applicationName)"
            ],
            shortTitle: "签到",
            systemImageName: "checkmark.seal"
        )
        AppShortcut(
            intent: CaptureClipboardIntent(),
            phrases: [
                "捕获剪贴板 \(.applicationName)"
            ],
            shortTitle: "捕获剪贴板",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: RefreshStatusIntent(),
            phrases: [
                "刷新 \(.applicationName) 状态"
            ],
            shortTitle: "刷新状态",
            systemImageName: "heart.text.square"
        )
    }
}
