import AppIntents
import SwiftUI

// MARK: - App Intents (Shortcuts / Siri)

@available(iOS 16.0, *)
struct OpenOverviewIntent: AppIntent {
    static var title: LocalizedStringResource = "打开总览"
    static var description = IntentDescription("打开 XIN's Tool 总览页。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 16.0, *)
struct OpenCheckinIntent: AppIntent {
    static var title: LocalizedStringResource = "打开签到中心"
    static var description = IntentDescription("打开签到中心查看状态。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 16.0, *)
struct CaptureClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "捕获剪贴板"
    static var description = IntentDescription("将当前剪贴板文本写入工具箱历史。")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let preview = await MainActor.run { () -> String in
            if let item = ClipboardStore.shared.capturePasteboard() {
                return item.preview
            }
            return "剪贴板为空或与上一条相同"
        }
        return .result(value: preview)
    }
}

@available(iOS 16.0, *)
struct RefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新服务状态"
    static var description = IntentDescription("探测已配置服务健康度并更新小组件数据。")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await MainActor.run {
            // Kick lightweight publish from current stores
            let c = ActivityEventStore.shared // touch
            _ = c
        }
        await ServiceHealthService.shared.probeAll()
        let fails = await MainActor.run {
            ServiceHealthService.shared.items.filter { $0.status == .fail }.count
        }
        let due = await MainActor.run { SubscriptionStore.shared.dueSoon.count }
        await MainActor.run {
            AppGroupShared.publish(
                checkinHealthy: 0,
                checkinTotal: 0,
                checkinFailed: 0,
                dueSubs: due,
                nextSubName: SubscriptionStore.shared.dueSoon.first?.name,
                nextSubDays: SubscriptionStore.shared.dueSoon.first?.daysUntilDue
            )
            ActivityEventStore.shared.log(.make(
                title: "快捷指令刷新",
                subtitle: fails == 0 ? "服务探测完成" : "\(fails) 项异常",
                systemImage: "arrow.triangle.2.circlepath",
                tintHex: fails == 0 ? 0x30D158 : 0xFF453A,
                route: "health"
            ))
        }
        return .result(value: fails == 0 ? "服务正常" : "\(fails) 项异常")
    }
}

@available(iOS 16.0, *)
struct ToolboxAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: OpenOverviewIntent(),
                phrases: ["打开 \(.applicationName) 总览", "打开总览 \(.applicationName)"],
                shortTitle: "总览",
                systemImageName: "square.grid.2x2"
            ),
            AppShortcut(
                intent: OpenCheckinIntent(),
                phrases: ["打开 \(.applicationName) 签到", "查看签到 \(.applicationName)"],
                shortTitle: "签到",
                systemImageName: "checkmark.seal"
            ),
            AppShortcut(
                intent: CaptureClipboardIntent(),
                phrases: ["捕获剪贴板 \(.applicationName)", "保存剪贴板 \(.applicationName)"],
                shortTitle: "捕获剪贴板",
                systemImageName: "doc.on.clipboard"
            ),
            AppShortcut(
                intent: RefreshStatusIntent(),
                phrases: ["刷新 \(.applicationName) 状态", "探测服务 \(.applicationName)"],
                shortTitle: "刷新状态",
                systemImageName: "heart.text.square"
            )
        ]
    }
}
