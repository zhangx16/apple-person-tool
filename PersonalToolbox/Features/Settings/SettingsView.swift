import SwiftUI

/// Credentials, connectivity probes, appearance, privacy, and logout-all.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @State private var confirmLogout = false
    @State private var favoriteDraft = ""

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

            Picker("首选模型", selection: $settings.preferredModel) {
                ForEach(viewModel.modelChoices, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            TextField("系统提示词", text: $settings.systemPrompt, axis: .vertical)
                .lineLimit(2...5)

            Button {
                Haptics.light()
                Task { await viewModel.testSub2API() }
            } label: {
                probeButtonLabel(title: "测试连接", busy: viewModel.sub2Probe.isProbing)
            }
            .disabled(viewModel.sub2Probe.isProbing)
            .buttonStyle(PressableButtonStyle())

            ServiceProbeRow(state: viewModel.sub2Probe)
        } header: {
            Label("AI（sub2api）", systemImage: "sparkles")
        } footer: {
            Text("Authorization: Bearer API Key。测试连接会调用 GET /v1/models。")
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
                Haptics.light()
                Task { await viewModel.testMail() }
            } label: {
                probeButtonLabel(title: "测试连接", busy: viewModel.mailProbe.isProbing)
            }
            .disabled(viewModel.mailProbe.isProbing)
            .buttonStyle(PressableButtonStyle())

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
                Haptics.light()
                Task { await viewModel.testYT() }
            } label: {
                probeButtonLabel(title: "测试连接", busy: viewModel.ytProbe.isProbing)
            }
            .disabled(viewModel.ytProbe.isProbing)
            .buttonStyle(PressableButtonStyle())

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

            Toggle("启动时需要面容/触控 ID", isOn: $settings.requireBiometricUnlock)

            Button(role: .destructive) {
                Haptics.light()
                confirmLogout = true
            } label: {
                Label("注销全部会话", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(PressableButtonStyle())
        } header: {
            Label("隐私与会话", systemImage: "lock.shield")
        } footer: {
            Text("生物识别锁默认关闭。注销仅清除本机 Cookie 与 Token，不会删除已保存的密钥。")
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
