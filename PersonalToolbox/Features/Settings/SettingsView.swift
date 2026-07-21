import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @State private var confirmLogout = false
    @State private var biometricAlert: String?
    @State private var isEnablingBiometric = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // 顶部概览卡：配置进度一目了然（LCSign 证书/状态卡思路）
                    configOverviewCard

                    settingsSection("服务配置", symbol: "server.rack") {
                        projectLink(
                            brand: .sub2,
                            title: "Sub2API 助手",
                            subtitle: hostHint(settings.sub2apiBaseURL),
                            configured: settings.isAIConfigured
                        ) {
                            Sub2ChatSettingsPage(viewModel: viewModel)
                        }
                        projectLink(
                            brand: .sub2,
                            title: "Sub2API 监控",
                            subtitle: settings.isAdminConfigured ? "Admin API Key" : "用于监控中心",
                            configured: settings.isAdminConfigured
                        ) {
                            Sub2AdminSettingsPage(viewModel: viewModel)
                        }
                        projectLink(
                            brand: .youtube,
                            title: "YouTube 下载",
                            subtitle: hostHint(settings.ytBaseURL),
                            configured: settings.isYTConfigured
                        ) {
                            YTSettingsPage(viewModel: viewModel)
                        }
                        projectLink(
                            brand: .sublink,
                            title: "SublinkX",
                            subtitle: hostHint(settings.sublinkBaseURL),
                            configured: settings.isSublinkConfigured
                        ) {
                            SublinkSettingsPage(viewModel: viewModel)
                        }
                        projectLink(
                            brand: .komari,
                            title: "Komari",
                            subtitle: hostHint(settings.komariBaseURL),
                            configured: !settings.komariBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            KomariSettingsPage(viewModel: viewModel)
                        }
                        projectLink(
                            brand: .checkin,
                            title: "签到服务",
                            subtitle: settings.isCheckinConfigured
                                ? hostHint(settings.checkinBaseURL)
                                : "glados-checkin-web · APP_API_TOKEN",
                            configured: settings.isCheckinConfigured
                        ) {
                            CheckinSettingsPage(viewModel: viewModel)
                        }
                        projectLink(
                            brand: .cloudflare,
                            title: "Cloudflare",
                            subtitle: settings.cloudflareAccountName.isEmpty
                                ? "API Token"
                                : settings.cloudflareAccountName,
                            configured: settings.isCloudflareConfigured
                        ) {
                            CloudflareSettingsPage(viewModel: viewModel)
                        }
                        plainLink(
                            systemImage: "shippingbox.fill",
                            title: "快递100",
                            subtitle: settings.kuaidi100Customer.isEmpty ? "实时查询凭证" : "customer 已填",
                            tint: ServiceBrand.express.tint,
                            configured: !settings.kuaidi100Customer.isEmpty
                        ) {
                            Kuaidi100SettingsPage()
                        }
                    }

                    settingsSection("直播 / 下载 Cookie", symbol: "play.tv.fill") {
                        plainLink(
                            systemImage: "music.note",
                            title: "抖音 Cookie",
                            subtitle: "直播搜索 / 本机下载",
                            tint: Color(hex: 0x111111),
                            configured: !settings.douyinLiveCookie.isEmpty
                        ) {
                            DouyinLiveSettingsPage()
                        }
                        plainLink(
                            systemImage: "video.fill",
                            title: "快手直播 Cookie",
                            subtitle: "匿名可播 · 弹幕可选",
                            tint: ServiceBrand.live.tint,
                            configured: !settings.kuaishouCookie.isEmpty
                        ) {
                            KuaishouLiveSettingsPage()
                        }
                        plainLink(
                            systemImage: "play.rectangle.on.rectangle.fill",
                            title: "B站 Cookie",
                            subtitle: "高清 / 大会员需登录",
                            tint: ServiceBrand.bilibili.tint,
                            configured: !settings.bilibiliCookie.isEmpty
                        ) {
                            BilibiliDownloadSettingsPage()
                        }
                    }

                    Text("密钥与 Cookie 仅保存在本机 Keychain / UserDefaults。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.top, -10)

                    settingsSection("通用", symbol: "slider.horizontal.3") {
                        plainLink(
                            systemImage: "bell.badge.fill",
                            title: "通知",
                            subtitle: settings.notifyDownloadCompleted ? "下载完成提醒已开" : "下载完成提醒已关",
                            tint: Color(hex: 0xFF9F0A)
                        ) {
                            NotificationSettingsPage()
                        }
                        plainLink(
                            systemImage: "paintbrush.fill",
                            title: "外观",
                            subtitle: appearanceLabel,
                            tint: Color(hex: 0xBF5AF2)
                        ) {
                            AppearanceSettingsPage()
                        }
                        plainLink(
                            systemImage: "lock.shield.fill",
                            title: "隐私与安全",
                            subtitle: settings.requireBiometricUnlock ? "应用锁已开启" : "应用锁关闭",
                            tint: Color(hex: 0x30D158),
                            configured: settings.requireBiometricUnlock
                        ) {
                            PrivacySettingsPage(
                                confirmLogout: $confirmLogout,
                                biometricAlert: $biometricAlert,
                                isEnablingBiometric: $isEnablingBiometric,
                                onLogout: { Task { await viewModel.logoutAllSessions() } }
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionTitle(title: "关于", systemImage: "info.circle")
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.accentColor.brandGradient)
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 48, height: 48)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("XIN's Tool")
                                        .font(.headline)
                                    Text("助手 · 直播 · 服务 · 本地工具")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                StatusPill(title: appVersion, color: .accentColor, systemImage: "tag.fill")
                            }
                            Divider().opacity(0.45)
                            Text("青绿工具风 UI · 凭证仅存本机 · 自托管优先")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .appCardV2()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(AppSurfaceBackground(accent: Color.accentColor))
            .navigationTitle("设置")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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

    private var configOverviewCard: some View {
        let items: [(String, Bool)] = [
            ("助手", settings.isAIConfigured),
            ("下载", settings.isYTConfigured),
            ("Sublink", settings.isSublinkConfigured),
            ("Cloudflare", settings.isCloudflareConfigured)
        ]
        let ready = items.filter(\.1).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("配置概览")
                        .font(.headline)
                    Text("\(ready)/\(items.count) 项核心服务已就绪")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(
                    title: ready == items.count ? "全部就绪" : "待完善",
                    color: ready == items.count ? Color(hex: 0x30D158) : Color.accentColor,
                    systemImage: ready == items.count ? "checkmark.seal.fill" : "ellipsis.circle.fill",
                    style: ready == items.count ? .solid : .soft
                )
            }
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { name, ok in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(ok ? Color(hex: 0x30D158) : Color.secondary.opacity(0.25))
                            .frame(width: 10, height: 10)
                        Text(name)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ok ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .appCardV2()
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: title, systemImage: symbol)
            VStack(spacing: 10) {
                content()
            }
        }
    }

    private func projectLink<Destination: View>(
        brand: ServiceBrand,
        title: String,
        subtitle: String,
        configured: Bool? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .environmentObject(settings)
        } label: {
            AppNavRow(
                title: title,
                subtitle: subtitle,
                brand: brand,
                trailingPill: configured.map { StatusPill.config($0) }
            )
            .appCard()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private func plainLink<Destination: View>(
        systemImage: String,
        title: String,
        subtitle: String,
        tint: Color = Color(hex: 0x0A84FF),
        configured: Bool? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .environmentObject(settings)
        } label: {
            AppNavRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint,
                trailingPill: configured.map { StatusPill.config($0) }
            )
            .appCard()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private func projectRow(
        systemImage: String,
        title: String,
        subtitle: String,
        tint: Color = Color(hex: 0x0A84FF)
    ) -> some View {
        // Kept for nested settings pages that still reference projectRow.
        AppNavRow(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
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

struct CheckinSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $settings.checkinBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("API Token (APP_API_TOKEN)", text: $settings.checkinAPIToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
            } header: {
                Text("glados-checkin-web")
            } footer: {
                Text("对应服务端 .env 的 APP_API_TOKEN。App 只读 /api/v1/summary，不保存各站 Cookie/密码。")
            }

            Section {
                ServiceProbeRow(state: viewModel.checkinProbe)
                Button {
                    Task { await viewModel.testCheckin() }
                } label: {
                    Label("测试签到接口", systemImage: "checkmark.seal")
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.checkinProbe.isProbing)
            } header: {
                Text("检测")
            }

            Section("说明") {
                Text("服务 Hub → 签到中心可查看 GLaDOS / EmbyMB / 周三晚 / Telegram Bot 等今日状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("签到服务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .checkin, title: "签到服务")
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

struct BilibiliDownloadSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextField("Cookie", text: $settings.bilibiliCookie, axis: .vertical)
                    .lineLimit(4...12)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("登录 Cookie（BilibiliDown 同思路）")
            } footer: {
                Text("浏览器登录 bilibili.com 后，复制 Cookie（建议含 SESSDATA、bili_jct、DedeUserID）。用于下载 Tab「B站」本机解析高清；不填也可下公开低清。")
            }
            Section("说明") {
                Text("参考 nICEnnnnnnnLee/BilibiliDown 的 Cookie 登录与 playurl 拉流；App 内优先单文件流，无需桌面 ffmpeg。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !settings.bilibiliCookie.isEmpty {
                    Button("清除 Cookie", role: .destructive) {
                        settings.bilibiliCookie = ""
                    }
                }
            }
        }
        .navigationTitle("B站 Cookie")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DouyinLiveSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextField("Cookie", text: $settings.douyinLiveCookie, axis: .vertical)
                    .lineLimit(4...12)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("登录 Cookie")
            } footer: {
                Text("在电脑浏览器打开 live.douyin.com 并登录后，F12 → Network 任选请求，复制 Request Headers 里的 Cookie（建议含 ttwid、sessionid、__ac_nonce 等）。用于搜索与部分房间拉流，降低风控。")
            }
            Section("获取步骤") {
                Text("1. 浏览器登录 live.douyin.com\n2. 打开开发者工具 → Network\n3. 刷新页面，点任意 live.douyin.com 请求\n4. 复制 Cookie 字段全文粘贴到上方")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("说明") {
                Text("不配置时使用内置匿名 Cookie，搜索/进房可能失败或触发验证。配置后即时生效，无需重启。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !settings.douyinLiveCookie.isEmpty {
                    Button("清除 Cookie", role: .destructive) {
                        settings.douyinLiveCookie = ""
                    }
                }
            }
        }
        .navigationTitle("抖音直播")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct KuaishouLiveSettingsPage: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextField("Cookie", text: $settings.kuaishouCookie, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Kww（可选）", text: $settings.kuaishouKww)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("登录凭证（弹幕）")
            } footer: {
                Text("列表与播放多数可匿名。弹幕需在浏览器登录 live.kuaishou.com 后复制 Cookie；若 Cookie 含 kwfv1= 会自动生成 Kww。与 SimpleLive「快手账号」一致。")
            }
            Section("说明") {
                Text("不配置 Cookie 也可看直播；仅弹幕连接可能提示凭证无效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("快手直播")
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

    private struct AppearanceOption: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let subtitle: String
    }

    private var options: [AppearanceOption] {
        [
            AppearanceOption(
                id: AppSettings.Appearance.system.rawValue,
                title: "跟随系统",
                symbol: "circle.lefthalf.filled",
                subtitle: "自动适配浅色 / 深色"
            ),
            AppearanceOption(
                id: AppSettings.Appearance.light.rawValue,
                title: "浅色",
                symbol: "sun.max.fill",
                subtitle: "始终使用浅色界面"
            ),
            AppearanceOption(
                id: AppSettings.Appearance.dark.rawValue,
                title: "深色",
                symbol: "moon.fill",
                subtitle: "始终使用深色界面"
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AppSectionTitle(title: "主题", systemImage: "paintbrush.fill")
                ForEach(options) { option in
                    appearanceRow(option)
                }
                Text("强调色采用青绿工具风（对齐 LCSign 类工具 App），部分控件随系统材质自动适配。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(AppSurfaceBackground())
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appearanceRow(_ option: AppearanceOption) -> some View {
        let selected = settings.appearance == option.id
        return Button {
            settings.appearance = option.id
            Haptics.light()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .appCard()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
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
