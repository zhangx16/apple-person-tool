import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @State private var confirmLogout = false
    @State private var biometricAlert: String?
    @State private var isEnablingBiometric = false

    var body: some View {
        NavigationStack {
            Form {
                sub2Section
                adminSection
                ytSection
                sublinkSection
                komariSection
                appearanceSection
                privacySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AppleTheme.canvas)
            .navigationTitle("设置")
            .confirmationDialog(
                "注销全部会话？",
                isPresented: $confirmLogout,
                titleVisibility: .visible
            ) {
                Button("注销全部会话", role: .destructive) {
                    Task { await viewModel.logoutAllSessions() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除下载 Token 与 SublinkX 登录态。密钥不会删除。")
            }
            .alert(
                "会话",
                isPresented: Binding(
                    get: { viewModel.logoutNotice != nil },
                    set: { if !$0 { viewModel.logoutNotice = nil } }
                )
            ) {
                Button("好", role: .cancel) { viewModel.logoutNotice = nil }
            } message: {
                Text(viewModel.logoutNotice ?? "")
            }
            .alert(
                "无法开启应用锁",
                isPresented: Binding(
                    get: { biometricAlert != nil },
                    set: { if !$0 { biometricAlert = nil } }
                )
            ) {
                Button("好", role: .cancel) { biometricAlert = nil }
            } message: {
                Text(biometricAlert ?? "")
            }
        }
    }

    // MARK: - Sub2API chat

    private var sub2Section: some View {
        Section {
            TextField("Base URL", text: $settings.sub2apiBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            SecureField("Chat API Key", text: $settings.sub2apiAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()

            Picker("首选文本模型", selection: $settings.preferredModel) {
                ForEach(viewModel.modelChoices, id: \.self) { Text($0).tag($0) }
            }
            Picker("默认生图模型", selection: $settings.preferredImagineImageModel) {
                ForEach(viewModel.imagineImageChoices, id: \.self) { Text($0).tag($0) }
            }
            Picker("默认编辑模型", selection: $settings.preferredImagineEditModel) {
                ForEach(viewModel.imagineEditChoices, id: \.self) { Text($0).tag($0) }
            }
            Picker("默认视频模型", selection: $settings.preferredImagineVideoModel) {
                ForEach(viewModel.imagineVideoChoices, id: \.self) { Text($0).tag($0) }
            }

            TextField("系统提示词", text: $settings.systemPrompt, axis: .vertical)
                .lineLimit(2...5)

            ServiceProbeRow(state: viewModel.sub2Probe)
            Button {
                Task { await viewModel.testSub2API() }
            } label: {
                Label("测试 Chat 连接", systemImage: "bolt.horizontal.circle")
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(viewModel.sub2Probe.isProbing)
        } header: {
            Text("Sub2API · 助手")
        } footer: {
            Text("用于对话与 Imagine。默认 \(settings.sub2apiBaseURL)")
        }
    }

    // MARK: - Admin monitor

    private var adminSection: some View {
        Section {
            SecureField("Admin API Key (x-api-key)", text: $settings.sub2apiAdminAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()

            ServiceProbeRow(state: viewModel.adminProbe)
            Button {
                Task { await viewModel.testAdmin() }
            } label: {
                Label("测试监控接口", systemImage: "chart.bar")
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(viewModel.adminProbe.isProbing)
        } header: {
            Text("Sub2API · 监控")
        } footer: {
            Text("对应 sub2api-mobile 的 Admin Token，访问 /api/v1/admin/dashboard/*。可与 Chat Key 不同。")
        }
    }

    // MARK: - yt-dlp

    private var ytSection: some View {
        Section {
            TextField("Base URL", text: $settings.ytBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField("用户名", text: $settings.ytUsername)
                .textInputAutocapitalization(.never)
            SecureField("密码", text: $settings.ytPassword)
                .privacySensitive()
            ServiceProbeRow(state: viewModel.ytProbe)
            Button {
                Task { await viewModel.testYT() }
            } label: {
                Label("测试下载服务", systemImage: "arrow.down.circle")
            }
            .buttonStyle(PressableButtonStyle())
        } header: {
            Text("yt-dlp Web UI")
        }
    }

    // MARK: - SublinkX

    private var sublinkSection: some View {
        Section {
            TextField("Base URL", text: $settings.sublinkBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField("用户名", text: $settings.sublinkUsername)
                .textInputAutocapitalization(.never)
            SecureField("密码", text: $settings.sublinkPassword)
                .privacySensitive()
            ServiceProbeRow(state: viewModel.sublinkProbe)
            Button {
                Task { await viewModel.testSublink() }
            } label: {
                Label("测试 SublinkX", systemImage: "link")
            }
            .buttonStyle(PressableButtonStyle())
        } header: {
            Text("SublinkX")
        } footer: {
            Text("默认 https://sub.996616.xyz · 登录需验证码（在服务页完成）")
        }
    }

    // MARK: - Komari

    private var komariSection: some View {
        Section {
            TextField("Base URL", text: $settings.komariBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            ServiceProbeRow(state: viewModel.komariProbe)
            Button {
                Task { await viewModel.testKomari() }
            } label: {
                Label("测试 Komari", systemImage: "server.rack")
            }
            .buttonStyle(PressableButtonStyle())
        } header: {
            Text("Komari 探针")
        } footer: {
            Text("默认 https://komari.996616.xyz · 使用公开 /api/nodes 接口")
        }
    }

    // MARK: - Appearance / privacy

    private var appearanceSection: some View {
        Section("外观") {
            Picker("主题", selection: $settings.appearance) {
                Text("跟随系统").tag(AppSettings.Appearance.system.rawValue)
                Text("浅色").tag(AppSettings.Appearance.light.rawValue)
                Text("深色").tag(AppSettings.Appearance.dark.rawValue)
            }
        }
    }

    private var privacySection: some View {
        Section("隐私与安全") {
            Toggle("应用切换时隐藏敏感内容", isOn: $settings.hideSensitiveInAppSwitcher)
            Toggle(
                "启动时需要面容/触控 ID",
                isOn: Binding(
                    get: { settings.requireBiometricUnlock },
                    set: { newValue in
                        if newValue {
                            Task { await enableBiometric() }
                        } else {
                            settings.requireBiometricUnlock = false
                        }
                    }
                )
            )
            .disabled(!BiometricAuth.canAuthenticate && !settings.requireBiometricUnlock)

            Button("注销全部会话", role: .destructive) {
                confirmLogout = true
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("应用", value: "PersonalToolbox")
            LabeledContent("版本", value: "1.1")
            Text("助手 · Sub2API 监控 · SublinkX · Komari · yt-dlp")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func enableBiometric() async {
        isEnablingBiometric = true
        defer { isEnablingBiometric = false }
        guard BiometricAuth.canAuthenticate else {
            biometricAlert = "设备未设置面容/触控 ID 或密码"
            return
        }
        let ok = await BiometricAuth.authenticate(reason: "开启应用锁")
        if ok {
            settings.requireBiometricUnlock = true
        } else {
            biometricAlert = "验证未通过，未开启应用锁"
        }
    }
}
