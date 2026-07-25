import SwiftUI

struct NavidromeSettingsView: View {
    @Environment(MeloXSettings.self) private var settings
    @State private var passwordDraft = ""
    @State private var isTesting = false
    @State private var statusText: String?
    @State private var statusOK = false

    private let client = NavidromeClient.shared

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("启用 Navidrome", isOn: $settings.navidromeEnabled)
                TextField("服务器地址", text: $settings.navidromeBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("用户名", text: $settings.navidromeUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: $passwordDraft)
                    .textContentType(.password)
                    .onAppear {
                        if passwordDraft.isEmpty {
                            passwordDraft = settings.navidromePassword
                        }
                    }
                    .onChange(of: passwordDraft) { _, new in
                        settings.navidromePassword = new
                    }
            } header: {
                Text("连接")
            } footer: {
                Text("兼容 OpenSubsonic / Navidrome。网易云无源或仅试听时，会自动按歌名+歌手在此曲库匹配并流式播放完整音轨。")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTesting {
                        ProgressView()
                    } else {
                        Label("测试连接", systemImage: "network")
                    }
                }
                .disabled(isTesting || !settings.navidromeIsConfigured)

                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusOK ? .green : .red)
                }
            } footer: {
                Text("启用后回退顺序：完整网易云 → Navidrome 完整流 → 网易云试听兜底。亦可长按歌曲「用 Navidrome 播放」。")
            }

            Section {
                LabeledContent("当前", value: settings.navidromeEnabled ? "已启用" : "关闭")
                LabeledContent("配置", value: settings.navidromeIsConfigured ? "完整" : "缺少地址/账号")
            } header: {
                Text("状态")
            }
        }
        .navigationTitle("Navidrome")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let info = try await client.ping(settings: settings)
            statusOK = true
            statusText = "连接成功：\(info)"
        } catch {
            statusOK = false
            statusText = error.localizedDescription
        }
    }
}
