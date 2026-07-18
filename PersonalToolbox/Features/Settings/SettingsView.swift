import SwiftUI

/// Credentials, connectivity probes, appearance, privacy, and logout-all.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @State private var confirmLogout = false
    @State private var favoriteDraft = ""
    @State private var biometricAlert: String?
    @State private var isEnablingBiometric = false

    var body: some View {
        NavigationStack {
            Form {
                sub2Section
                mailSection
                ytSection
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
                Text("将清除本机邮件 Cookie 与下载 Token。服务端账号与密钥不会删除。")
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

    // MARK: - sub2api

    private var sub2Section: some View {
        Section {
            TextField("Base URL", text: $settings.sub2apiBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            SecureField("API Key", text: $settings.sub2apiAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()

            Picker("首选文本模型", selection: $settings.preferredModel) {
                ForEach(viewModel.modelChoices, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            Picker("默认生图模型", selection: $settings.preferredImagineImageModel) {
                ForEach(viewModel.imagineImageChoices, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            Picker("默认编辑模型", selection: $settings.preferredImagineEditModel) {
                ForEach(viewModel.imagineEditChoices, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            Picker("默认视频模型", selection: $settings.preferredImagineVideoModel) {
                ForEach(viewModel.imagineVideoChoices, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            TextField("系统提示词", text: $settings.systemPrompt, axis: .vertical)
                .lineLimit(2...5)

            Button {
                Task { await viewModel.testSub2API() }
            } label: {
                probeButtonLabel(title: "测试连接", busy: viewModel.sub2Probe.isProbing)
            }
            .disabled(viewModel.sub2Probe.isProbing)
            .buttonStyle(PressableButtonStyle())
            .accessibilityHint("探测 sub2api 连通性")

            ServiceProbeRow(state: viewModel.sub2Probe)
        } header: {
            Label("AI（sub2api）", systemImage: "sparkles")
        } footer: {
            Text("Authorization: Bearer API Key。测试连接会调用 GET /v1/models。文本与 Imagine 模型列表分离。")
        }
    }

    // MARK: - mail

    private var mailSection: some View {
        Section {
            TextField("Base URL", text: $settings.mailBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            Picker("认证方式", selection: $settings.mailUseExternalAPI) {
                Text("管理密码登录").tag(false)
                Text("外部 API Key").tag(true)
            }

            if settings.mailUseExternalAPI {
                SecureField("外部 API Key", text: $settings.mailExternalAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                TextField("默认邮箱", text: $settings.mailDefaultEmail)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)

                // Favorite mailboxes (optional; shown as virtual accounts on Mail tab).
                HStack {
                    TextField("添加收藏邮箱", text: $favoriteDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .submitLabel(.done)
                        .onSubmit { addFavoriteEmail() }
                    Button {
                        addFavoriteEmail()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(favoriteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("添加收藏邮箱")
                }

                ForEach(settings.normalizedMailFavoriteEmails, id: \.self) { email in
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(email)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button(role: .destructive) {
                            settings.removeMailFavoriteEmail(email)
                            Haptics.light()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.85))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("移除 \(email)")
                    }
                }
            } else {
                SecureField("管理密码", text: $settings.mailPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
            }

            Button {
                Task { await viewModel.testMail() }
            } label: {
                probeButtonLabel(title: "测试连接", busy: viewModel.mailProbe.isProbing)
            }
            .disabled(viewModel.mailProbe.isProbing)
            .buttonStyle(PressableButtonStyle())
            .accessibilityHint("探测邮件服务连通性")

            ServiceProbeRow(state: viewModel.mailProbe)
        } header: {
            Label("邮件", systemImage: "envelope")
        } footer: {
            Text(
                settings.mailUseExternalAPI
                    ? "外部模式走 X-API-Key，列表/详情均带 email；默认邮箱必填，收藏邮箱可选。探测 /api/external/health。"
                    : "会话登录：探测 ensureSession 并列出账号。Cookie 存于 App 隔离存储。"
            )
        }
    }

    private func addFavoriteEmail() {
        let draft = favoriteDraft
        guard settings.addMailFavoriteEmail(draft) else {
            Haptics.error()
            return
        }
        favoriteDraft = ""
        Haptics.light()
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
                .autocorrectionDisabled()
                .textContentType(.username)

            SecureField("密码", text: $settings.ytPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .privacySensitive()

            Button {
                Task { await viewModel.testYT() }
            } label: {
                probeButtonLabel(title: "测试连接", busy: viewModel.ytProbe.isProbing)
            }
            .disabled(viewModel.ytProbe.isProbing)
            .buttonStyle(PressableButtonStyle())
            .accessibilityHint("探测下载服务连通性")

            ServiceProbeRow(state: viewModel.ytProbe)
        } header: {
            Label("下载（yt-dlp）", systemImage: "arrow.down.circle")
        } footer: {
            Text("测试连接会登录并请求 /api/v1/version。")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("外观", selection: $settings.appearance) {
                Text("跟随系统").tag(AppSettings.Appearance.system.rawValue)
                Text("浅色").tag(AppSettings.Appearance.light.rawValue)
                Text("深色").tag(AppSettings.Appearance.dark.rawValue)
            }
            .pickerStyle(.segmented)
        } header: {
            Label("外观", systemImage: "circle.lefthalf.filled")
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Toggle("应用切换时隐藏敏感内容", isOn: $settings.hideSensitiveInAppSwitcher)
                .accessibilityHint("切到后台或应用切换器时用遮罩隐藏界面")

            Toggle("启动时需要面容/触控 ID", isOn: biometricUnlockBinding)
                .disabled(isEnablingBiometric || (!BiometricAuth.canAuthenticate && !settings.requireBiometricUnlock))
                .accessibilityHint(
                    BiometricAuth.canAuthenticate || settings.requireBiometricUnlock
                        ? "每次进入应用需验证设备所有者身份；开启前会先验证一次"
                        : "设备未设置面容 ID、触控 ID 或密码，无法开启"
                )

            Button(role: .destructive) {
                confirmLogout = true
            } label: {
                Label("注销全部会话", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityHint("清除本机邮件 Cookie 与下载 Token")
        } header: {
            Label("隐私与会话", systemImage: "lock.shield")
        } footer: {
            Text(privacyFooterText)
        }
    }

    private var privacyFooterText: String {
        if !BiometricAuth.canAuthenticate && !settings.requireBiometricUnlock {
            return "生物识别锁默认关闭。此设备未设置面容 ID、触控 ID 或设备密码，无法开启应用锁。注销仅清除本机 Cookie 与 Token，不会删除已保存的密钥。"
        }
        return "生物识别锁默认关闭。开启前会先验证身份；之后从后台返回也需重新验证。注销仅清除本机 Cookie 与 Token，不会删除已保存的密钥。"
    }

    /// Binding that only commits `true` after a successful auth preflight (review Issue 3).
    private var biometricUnlockBinding: Binding<Bool> {
        Binding(
            get: { settings.requireBiometricUnlock },
            set: { newValue in
                if newValue {
                    Task { await enableBiometricUnlock() }
                } else {
                    settings.requireBiometricUnlock = false
                }
            }
        )
    }

    @MainActor
    private func enableBiometricUnlock() async {
        guard !isEnablingBiometric else { return }
        guard BiometricAuth.canAuthenticate else {
            biometricAlert = "此设备未设置面容 ID、触控 ID 或设备密码，无法开启应用锁。"
            Haptics.error()
            return
        }
        isEnablingBiometric = true
        defer { isEnablingBiometric = false }
        let ok = await BiometricAuth.authenticate(reason: "验证身份以开启应用锁")
        if ok {
            settings.requireBiometricUnlock = true
            Haptics.success()
        } else {
            // Keep setting off so user is never locked out without a successful enable.
            settings.requireBiometricUnlock = false
            biometricAlert = "验证失败或已取消，未开启应用锁。"
            Haptics.error()
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("应用", value: "PersonalToolbox")
            LabeledContent("平台", value: "iOS 17+")
        } header: {
            Text("关于")
        } footer: {
            Text("公网 HTTPS 服务请配合 VPN/白名单与定期轮换密钥使用。")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func probeButtonLabel(title: String, busy: Bool) -> some View {
        HStack {
            if busy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            Text(title)
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
