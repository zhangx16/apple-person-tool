import SwiftUI

/// Unified control center: notifications, clipboard bar, live open alerts, privacy.
struct ControlCenterView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var deniedHint: String?
    @State private var testOK = false

    var body: some View {
        List {
            Section {
                Text("统一管理本地通知、剪贴板智能条与直播开播提醒。总览刷新时会评估签到 / 账单 / 证书 / 开播。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("通知总控") {
                Toggle("智能提醒总开关", isOn: $settings.notifySmartAlerts)
                Toggle("下载完成通知", isOn: $settings.notifyDownloadCompleted)
                Toggle("签到失败", isOn: $settings.notifyCheckinFailed)
                    .disabled(!settings.notifySmartAlerts)
                Toggle("订阅即将到期", isOn: $settings.notifySubscriptionDue)
                    .disabled(!settings.notifySmartAlerts)
                Toggle("证书即将到期", isOn: $settings.notifyCertExpiry)
                    .disabled(!settings.notifySmartAlerts)
                Toggle("关注主播开播", isOn: $settings.notifyLiveOpen)
                    .disabled(!settings.notifySmartAlerts)
            }

            Section("免打扰") {
                Toggle("开启安静时段", isOn: $settings.notifyQuietHoursEnabled)
                    .disabled(!settings.notifySmartAlerts)
                if settings.notifyQuietHoursEnabled {
                    Stepper(
                        "开始 \(settings.notifyQuietStartHour):00",
                        value: $settings.notifyQuietStartHour,
                        in: 0...23
                    )
                    Stepper(
                        "结束 \(settings.notifyQuietEndHour):00",
                        value: $settings.notifyQuietEndHour,
                        in: 0...23
                    )
                    Text("默认 23:00–08:00 不发开播/签到/账单/证书；下载完成仍通知。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("剪贴板") {
                Toggle("智能条（识别链接 / IP / 单号）", isOn: $settings.clipboardSmartBarEnabled)
                Text("切到前台或切换 Tab 时检测剪贴板；10 分钟冷却；可「不再提示此类」。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !settings.clipboardMutedKinds.isEmpty {
                    Button("清除已静音类型 (\(settings.clipboardMutedKinds.count))") {
                        settings.clipboardMutedKinds = []
                    }
                }
            }

            Section("权限") {
                Button("请求通知权限") {
                    Task {
                        let ok = await LocalNotifier.ensureAuthorized()
                        deniedHint = ok ? nil : "未获得通知权限，请到系统设置开启"
                        testOK = ok
                    }
                }
                if let deniedHint {
                    Text(deniedHint).font(.caption).foregroundStyle(.orange)
                }
                Button("发送测试通知") {
                    Task {
                        let ok = await LocalNotifier.ensureAuthorized()
                        guard ok else {
                            deniedHint = "未获得通知权限"
                            return
                        }
                        LocalNotifier.notify(
                            id: "test.control.\(UUID().uuidString)",
                            title: "控制中心",
                            body: "通知通道正常",
                            category: LocalNotifier.smartCategory,
                            userInfo: ["route": "settings"]
                        )
                        testOK = true
                    }
                }
                if testOK {
                    Text("已发送 / 权限正常").font(.caption).foregroundStyle(.green)
                }
            }

            Section("快捷入口") {
                NavigationLink {
                    IPCheckHomeView()
                } label: {
                    Label("IP 检测 / 节点档案", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
        .navigationTitle("控制中心")
        .navigationBarTitleDisplayMode(.inline)
    }
}
