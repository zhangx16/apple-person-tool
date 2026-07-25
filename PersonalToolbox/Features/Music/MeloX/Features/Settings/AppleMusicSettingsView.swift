import SwiftUI
import MusicKit

struct AppleMusicSettingsView: View {
    @Environment(MeloXSettings.self) private var settings
    @Environment(PlayerStore.self) private var player

    @State private var isRefreshing = false
    @State private var statusNote: String?
    @State private var stats = AppleMusicRescueStats.shared

    private let bridge = AppleMusicBridge.shared
    private let matchCache = AppleMusicMatchCache.shared

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                statusRow(
                    title: "媒体权限",
                    value: authorizationLabel,
                    systemImage: "hand.raised.fill"
                )
                statusRow(
                    title: "曲库播放",
                    value: subscriptionLabel,
                    systemImage: "music.note.house.fill"
                )
                statusRow(
                    title: "当前音源",
                    value: player.sourceLayerTitle,
                    systemImage: "waveform"
                )

                Button {
                    Task { await connect() }
                } label: {
                    Label(
                        bridge.isAuthorized ? "重新检查订阅" : "连接 Apple Music",
                        systemImage: bridge.isAuthorized ? "arrow.clockwise" : "link"
                    )
                }
                .disabled(isRefreshing)

                if let statusNote {
                    Text(statusNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("状态")
            } footer: {
                Text("应用内 MusicKit 真播放需要：① 苹果开发者后台为 App ID 开启 MusicKit ② 用含该能力的描述文件重签 ③ 本机登录 Apple Music 会员。若出现 developer token 失败，App 会用 iTunes 搜索并跳转系统「音乐」播放完整版。")
            }

            Section {
                Picker("音源策略", selection: $settings.audioSourcePolicy) {
                    ForEach(AudioSourcePolicy.allCases) { policy in
                        Label(policy.title, systemImage: policy.systemImage)
                            .tag(policy)
                    }
                }
                .pickerStyle(.inline)

                Text(settings.audioSourcePolicy.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("策略")
            }

            Section {
                Toggle("列表隐藏 VIP/付费/无版权", isOn: $settings.hideLikelyIncompleteTracks)
                Text("按网易云 fee/版权字段启发式过滤，减少点到试听曲。已登录会员仍可能完整可播。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("列表")
            }

            Section {
                LabeledContent("近 7 天救场", value: "\(stats.weekCount) 次")
                LabeledContent("近 30 天", value: "\(stats.monthCount) 次")
                LabeledContent("累计", value: "\(stats.totalCount) 次")
                LabeledContent("已记住匹配", value: "\(matchCache.count) 首")

                if stats.totalCount > 0 {
                    Button("清空救场统计", role: .destructive) {
                        stats.clear()
                    }
                }
                if matchCache.count > 0 {
                    Button("清空匹配缓存", role: .destructive) {
                        matchCache.clear()
                    }
                }
            } header: {
                Text("统计")
            } footer: {
                Text("「救场」= 因无源/试听/策略而成功切到 Apple Music 完整播放的次数。")
            }

            if player.isUsingAppleMusic {
                Section {
                    Button("更换 Apple Music 匹配…") {
                        Task { await player.presentAppleMusicMatchPicker() }
                    }
                    if let label = player.appleMusicMatchLabel {
                        Text("当前：\(label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("当前播放")
                }
            }
        }
        .navigationTitle("Apple Music")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshQuiet()
        }
    }

    private var authorizationLabel: String {
        switch bridge.authorizationStatus {
        case .authorized: "已授权"
        case .denied: "已拒绝"
        case .restricted: "受限制"
        case .notDetermined: "未请求"
        @unknown default: "未知"
        }
    }

    private var subscriptionLabel: String {
        guard bridge.subscriptionChecked else { return "未检查" }
        return bridge.canPlayCatalogContent ? "可播曲库（会员）" : "不可播曲库 / 非会员"
    }

    private func statusRow(title: String, value: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func connect() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let status = await bridge.requestAuthorization()
        await bridge.refreshSubscriptionStatus()
        switch status {
        case .authorized:
            statusNote = bridge.canPlayCatalogContent
                ? "已连接，可以使用曲库真播放。"
                : "权限已开，但当前账号似乎无法播放曲库（检查 Apple Music 会员）。"
        case .denied:
            statusNote = "权限被拒。请到 系统设置 → 本 App → 开启媒体与 Apple Music。"
        case .restricted:
            statusNote = "设备策略限制了 Apple Music。"
        default:
            statusNote = "未能完成授权。"
        }
    }

    private func refreshQuiet() async {
        isRefreshing = true
        defer { isRefreshing = false }
        if bridge.isAuthorized {
            await bridge.refreshSubscriptionStatus()
        }
    }
}
