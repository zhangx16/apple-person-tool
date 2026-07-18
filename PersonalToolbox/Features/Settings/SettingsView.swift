import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @State private var confirmLogout = false
    @State private var biometricAlert: String?
    @State private var isEnablingBiometric = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    projectLink(
                        brand: .sub2,
                        title: "Sub2API 助手",
                        subtitle: configuredHint(
                            configured: settings.isAIConfigured,
                            detail: hostHint(settings.sub2apiBaseURL)
                        )
                    ) {
                        Sub2ChatSettingsPage(viewModel: viewModel)
                    }

                    projectLink(
                        brand: .sub2,
                        title: "Sub2API 监控",
                        subtitle: configuredHint(
                            configured: settings.isAdminConfigured,
                            detail: "Admin API Key"
                        )
                    ) {
                        Sub2AdminSettingsPage(viewModel: viewModel)
                    }

                    projectLink(
                        brand: .youtube,
                        title: "YouTube 下载",
                        subtitle: configuredHint(
                            configured: settings.isYTConfigured,
                            detail: hostHint(settings.ytBaseURL)
                        )
                    ) {
                        YTSettingsPage(viewModel: viewModel)
                    }

                    projectLink(
                        brand: .sublink,
                        title: "SublinkX",
                        subtitle: configuredHint(
                            configured: settings.isSublinkConfigured,
                            detail: hostHint(settings.sublinkBaseURL)
                        )
                    ) {
                        SublinkSettingsPage(viewModel: viewModel)
                    }

                    projectLink(
                        brand: .komari,
                        title: "Komari",
                        subtitle: hostHint(settings.komariBaseURL)
                    ) {
                        KomariSettingsPage(viewModel: viewModel)
                    }

                    projectLink(
                        brand: .cloudflare,
                        title: "Cloudflare",
                        subtitle: configuredHint(
                            configured: settings.isCloudflareConfigured,
                            detail: settings.cloudflareAccountName.isEmpty
                                ? "API Token"
                                : settings.cloudflareAccountName
                        )
                    ) {
                        CloudflareSettingsPage(viewModel: viewModel)
                    }

                    NavigationLink {
                        Kuaidi100SettingsPage()
                    } label: {
                        projectRow(
                            systemImage: "shippingbox.fill",
                            title: "快递100",
                            subtitle: settings.kuaidi100Customer.isEmpty ? "未配置" : "customer 已填"
                        )
                    }
                } header: {
                    Text("服务配置")
                } footer: {
                    Text("仅显示项目名称，点进各自页面填写地址与密钥。")
                }

                Section("通用") {
                    NavigationLink {
                        NotificationSettingsPage()
                    } label: {
                        projectRow(
                            systemImage: "bell.badge.fill",
                            title: "通知",
                            subtitle: settings.notifyDownloadCompleted ? "下载完成提醒已开" : "下载完成提醒已关"
                        )
                    }

                    NavigationLink {
                        AppearanceSettingsPage()
                    } label: {
                        projectRow(
                            systemImage: "paintbrush.fill",
                            title: "外观",
                            subtitle: appearanceLabel
                        )
                    }

                    NavigationLink {
                        PrivacySettingsPage(
                            confirmLogout: $confirmLogout,
                            biometricAlert: $biometricAlert,
                            isEnablingBiometric: $isEnablingBiometric,
                            onLogout: { Task { await viewModel.logoutAllSessions() } }
                        )
                    } label: {
                        projectRow(
                            systemImage: "lock.shield.fill",
                            title: "隐私与安全",
                            subtitle: settings.requireBiometricUnlock ? "应用锁已开启" : "应用锁关闭"
                        )
                    }
                }

                Section("关于") {
                    LabeledContent("应用", value: "XIN's Tool")
                    LabeledContent("版本", value: appVersion)
                    Text("助手 · 监控 · 下载 · 本地工具")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
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

    // MARK: - Home rows

    private func projectLink<Destination: View>(
        brand: ServiceBrand,
        title: String,
        subtitle: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .environmentObject(settings)
        } label: {
            HStack(spacing: 14) {
                ServiceBrandIcon(brand: brand, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)，\(subtitle)")
        }
    }

    private func projectRow(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func configuredHint(configured: Bool, detail: String) -> String {
        if configured {
            return detail.isEmpty ? "已配置" : detail
        }
        return "未配置"
    }

    private func hostHint(_ baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return trimmed.isEmpty ? "未配置" : trimmed
        }
        return host
    }

    private var appearanceLabel: String {
        switch AppSettings.Appearance(rawValue: settings.appearance) {
        case .light: return "浅色"
        case .dark: return "深色"
        default: return "跟随系统"
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

// MARK: - Project detail pages

struct Sub2ChatSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $settings.sub2apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Chat API Key", text: $settings.sub2apiAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
            } header: {
                Text("连接")
            } footer: {
                Text("用于对话与 Imagine。")
            }

            Section("模型") {
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
            }

            Section("系统提示词") {
                TextField("系统提示词", text: $settings.systemPrompt, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                ServiceProbeRow(state: viewModel.sub2Probe)
                Button {
                    Task { await viewModel.testSub2API() }
                } label: {
                    Label("测试 Chat 连接", systemImage: "bolt.horizontal.circle")
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.sub2Probe.isProbing)
            } header: {
                Text("检测")
            }
        }
        .navigationTitle("Sub2API 助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .sub2, title: "Sub2API 助手")
            }
        }
    }
}

struct Sub2AdminSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                SecureField("Admin API Key (x-api-key)", text: $settings.sub2apiAdminAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
            } header: {
                Text("凭证")
            } footer: {
                Text("对应 sub2api-mobile 的 Admin Token，访问 /api/v1/admin/*。可与 Chat Key 不同。Base URL 与「Sub2API 助手」共用。")
            }

            Section {
                LabeledContent("Base URL", value: settings.sub2apiBaseURL)
                ServiceProbeRow(state: viewModel.adminProbe)
                Button {
                    Task { await viewModel.testAdmin() }
                } label: {
                    Label("测试监控接口", systemImage: "chart.bar")
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.adminProbe.isProbing)
            } header: {
                Text("检测")
            }
        }
        .navigationTitle("Sub2API 监控")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .sub2, title: "Sub2API 监控")
            }
        }
    }
}

struct YTSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $settings.ytBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("用户名", text: $settings.ytUsername)
                    .textInputAutocapitalization(.never)
                SecureField("密码", text: $settings.ytPassword)
                    .privacySensitive()
            } header: {
                Text("yt-dlp-web-ui")
            } footer: {
                Text("YouTube 等通用视频下载走此服务。抖音在下载 Tab 本机解析，无需此项。")
            }

            Section {
                ServiceProbeRow(state: viewModel.ytProbe)
                Button {
                    Task { await viewModel.testYT() }
                } label: {
                    Label("测试下载服务", systemImage: "arrow.down.circle")
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .navigationTitle("YouTube 下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .youtube, title: "YouTube 下载")
            }
        }
    }
}

struct SublinkSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $settings.sublinkBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("用户名", text: $settings.sublinkUsername)
                    .textInputAutocapitalization(.never)
                SecureField("密码", text: $settings.sublinkPassword)
                    .privacySensitive()
            } footer: {
                Text("登录需验证码时，在服务页 SublinkX 完成。")
            }

            Section {
                ServiceProbeRow(state: viewModel.sublinkProbe)
                Button {
                    Task { await viewModel.testSublink() }
                } label: {
                    Label("测试 SublinkX", systemImage: "link")
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .navigationTitle("SublinkX")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .sublink, title: "SublinkX")
            }
        }
    }
}

struct KomariSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $settings.komariBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } footer: {
                Text("使用公开 /api/nodes 接口。")
            }

            Section {
                ServiceProbeRow(state: viewModel.komariProbe)
                Button {
                    Task { await viewModel.testKomari() }
                } label: {
                    Label("测试 Komari", systemImage: "server.rack")
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .navigationTitle("Komari")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .komari, title: "Komari")
            }
        }
    }
}

struct CloudflareSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                SecureField("API Token / Global Key", text: $settings.cloudflareAPIToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                TextField("Email（仅 Global Key 时填写）", text: $settings.cloudflareEmail)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                TextField("Account ID", text: $settings.cloudflareAccountId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !settings.cloudflareAccountName.isEmpty {
                    LabeledContent("账户名", value: settings.cloudflareAccountName)
                }
            } footer: {
                Text("推荐 API Token（Bearer）。填写 Email 时按 Global API Key 鉴权。Account ID 用于 Workers/Pages 用量。")
            }

            Section {
                ServiceProbeRow(state: viewModel.cloudflareProbe)
                Button {
                    Task { await viewModel.testCloudflare() }
                } label: {
                    Label("测试 Cloudflare", systemImage: "bolt.fill")
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.cloudflareProbe.isProbing)
                Button {
                    Task { await viewModel.fetchCloudflareAccounts() }
                } label: {
                    Label("拉取账户并填入第一个", systemImage: "person.2")
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.cloudflareProbe.isProbing)
            }
        }
        .navigationTitle("Cloudflare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .cloudflare, title: "Cloudflare")
            }
        }
    }
}

struct Kuaidi100SettingsPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextField("Customer", text: $settings.kuaidi100Customer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("授权 Key", text: $settings.kuaidi100Key)
                    .textInputAutocapitalization(.never)
                    .privacySensitive()
            } header: {
                Text("实时查询凭证")
            } footer: {
                Text("与官网 Python/Java 示例相同：POST poll/query.do，sign=MD5(param+key+customer)。Customer 与授权 Key 已可预填，Key 存 Keychain。")
            }
            Section("说明") {
                Text("「智能单号识别」若提示 key 过期，不影响实时查询：App 会按单号规则与多家公司编码回退尝试。顺丰建议填手机后四位。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("快递100")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var authLabel = "读取中…"
    @State private var deniedHint: String?

    var body: some View {
        Form {
            Section {
                Toggle(
                    "下载完成时通知",
                    isOn: Binding(
                        get: { settings.notifyDownloadCompleted },
                        set: { newValue in
                            if newValue {
                                Task { await enableDownloadNotify() }
                            } else {
                                settings.notifyDownloadCompleted = false
                            }
                        }
                    )
                )
            } header: {
                Text("下载")
            } footer: {
                Text("YouTube 队列与抖音本机下载结束时发送本地通知（含失败）。纪念日提醒在「服务 → 纪念日」中单独配置。")
            }

            Section {
                LabeledContent("系统权限", value: authLabel)
                Button("请求通知权限") {
                    Task {
                        _ = await LocalNotifier.requestAuthorization()
                        await refreshAuthLabel()
                    }
                }
                if deniedHint != nil {
                    Text(deniedHint!)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("权限")
            } footer: {
                Text("若已拒绝，请到系统设置 → 通知 → XIN's Tool 中开启。")
            }

            Section {
                Button("发送测试通知") {
                    Task {
                        let ok = await LocalNotifier.ensureAuthorized()
                        await refreshAuthLabel()
                        guard ok else {
                            deniedHint = "未获得通知权限"
                            return
                        }
                        LocalNotifier.notify(
                            id: "download.test.\(UUID().uuidString)",
                            title: "测试通知",
                            body: "下载完成提醒工作正常。"
                        )
                    }
                }
            }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthLabel() }
    }

    private func enableDownloadNotify() async {
        let ok = await LocalNotifier.ensureAuthorized()
        await refreshAuthLabel()
        if ok {
            settings.notifyDownloadCompleted = true
            deniedHint = nil
        } else {
            settings.notifyDownloadCompleted = false
            deniedHint = "未获得通知权限，无法开启下载提醒"
        }
    }

    private func refreshAuthLabel() async {
        let status = await LocalNotifier.authorizationStatus()
        switch status {
        case .authorized: authLabel = "已授权"
        case .provisional: authLabel = "临时授权"
        case .denied: authLabel = "已拒绝"
        case .notDetermined: authLabel = "尚未请求"
        case .ephemeral: authLabel = "临时"
        @unknown default: authLabel = "未知"
        }
    }
}

struct AppearanceSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("主题", selection: $settings.appearance) {
                    Text("跟随系统").tag(AppSettings.Appearance.system.rawValue)
                    Text("浅色").tag(AppSettings.Appearance.light.rawValue)
                    Text("深色").tag(AppSettings.Appearance.dark.rawValue)
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacySettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var confirmLogout: Bool
    @Binding var biometricAlert: String?
    @Binding var isEnablingBiometric: Bool
    var onLogout: () -> Void

    var body: some View {
        Form {
            Section {
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
            }

            Section {
                Button("注销全部会话", role: .destructive) {
                    confirmLogout = true
                }
            } footer: {
                Text("清除下载 Token、SublinkX 登录态与 Cookie。已保存的密钥不会删除。")
            }
        }
        .navigationTitle("隐私与安全")
        .navigationBarTitleDisplayMode(.inline)
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
