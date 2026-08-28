// Overview home — first tab
import SwiftUI

// MARK: - ViewModel

@MainActor
final class OverviewViewModel: ObservableObject {
    struct AttentionItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let tint: Color
        let systemImage: String
        let destination: OverviewDestination
    }

    enum OverviewDestination: Hashable {
        case checkin
        case serviceHealth
        case download
        case sub2Monitor
        case cloudflare
        case ipCheck
        case servicesTab
        case liveTab
        case musicTab
        case settingsTab
        case checkinSettings
        case notes
        case reminders
        case subscriptions
        case controlCenter
        case proxyPack
        case watchLater
        case expressAssistant
        case qrAssistant
        case translator
        case market
        case novel
        case telegramChannel
        case sublink
    }

    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var checkinSummary: CheckinSummary?
    @Published private(set) var healthItems: [ServiceHealthItem] = []
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var activity: [ActivityEvent] = []
    @Published private(set) var liveNowCount = 0
    @Published private(set) var liveNowNames: [String] = []
    @Published private(set) var subsDueSoon: [SubscriptionItem] = []
    @Published private(set) var watchLaterCount = 0

    private let checkin = CheckinService.shared
    private let health = ServiceHealthService.shared
    private let activityStore = ActivityEventStore.shared

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    var dateLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    var headlineStatus: String {
        var bits: [String] = []
        if liveNowCount > 0 { bits.append("\(liveNowCount) 位主播直播中") }
        if !subsDueSoon.isEmpty { bits.append("\(subsDueSoon.count) 笔账单将到期") }
        if healthFail > 0 { bits.append("\(healthFail) 项服务异常") }
        if bits.isEmpty {
            let healthy = checkinSummary?.counts?.healthyValue
            let total = checkinSummary?.counts?.totalValue
            if let healthy, let total, total > 0 {
                return "签到 \(healthy)/\(total) 正常 · 服务运行平稳"
            }
            return "一切顺利 · 从下方进入常用服务"
        }
        return bits.joined(separator: " · ")
    }

    var attentionItems: [AttentionItem] {
        var list: [AttentionItem] = []

        if liveNowCount > 0 {
            list.append(.init(
                id: "live-now",
                title: "\(liveNowCount) 位关注主播直播中",
                subtitle: liveNowNames.prefix(3).joined(separator: "、") + (liveNowNames.count > 3 ? " 等" : ""),
                tint: Color(hex: 0xFF375F),
                systemImage: "dot.radiowaves.left.and.right",
                destination: .liveTab
            ))
        }

        if !AppSettings.shared.isCheckinConfigured {
            list.append(.init(
                id: "cfg-checkin",
                title: "签到服务未配置",
                subtitle: "设置 API Token 后可查看每日状态",
                tint: Color(hex: 0xFF9F0A),
                systemImage: "key.fill",
                destination: .checkinSettings
            ))
        } else if let projects = checkinSummary?.projects {
            let bad = projects.filter { $0.statusKind == .failed }
            if !bad.isEmpty {
                let names = bad.prefix(2).map(\.displayTitle).joined(separator: "、")
                list.append(.init(
                    id: "checkin-fail",
                    title: "\(bad.count) 个签到项目异常",
                    subtitle: names + (bad.count > 2 ? " 等" : ""),
                    tint: Color(hex: 0xFF453A),
                    systemImage: "exclamationmark.triangle.fill",
                    destination: .checkin
                ))
            }
        }

        for item in healthItems where item.status == .fail {
            list.append(.init(
                id: "health-\(item.id)",
                title: "\(item.title) 异常",
                subtitle: item.detail,
                tint: Color(hex: 0xFF453A),
                systemImage: "bolt.horizontal.circle.fill",
                destination: .serviceHealth
            ))
        }

        if let first = subsDueSoon.first {
            list.append(.init(
                id: "sub-due",
                title: "\(subsDueSoon.count) 笔订阅 14 天内到期",
                subtitle: "\(first.name) · \(first.daysUntilDue) 天 · \(String(format: "%.2f", first.amount)) \(first.currency)",
                tint: Color(hex: 0xFF9F0A),
                systemImage: "creditcard.fill",
                destination: .subscriptions
            ))
        }

        return list
    }

    var checkinHealthy: Int { checkinSummary?.counts?.healthyValue ?? 0 }
    var checkinTotal: Int { checkinSummary?.counts?.totalValue ?? 0 }
    var checkinFailed: Int { checkinSummary?.counts?.failedValue ?? 0 }
    var checkinProjects: Int {
        checkinSummary?.counts?.projectTotalValue
            ?? checkinSummary?.projects?.count
            ?? 0
    }

    var healthOK: Int { healthItems.filter { $0.status == .ok }.count }
    var healthFail: Int { healthItems.filter { $0.status == .fail }.count }
    var healthConfigured: Int { healthItems.filter { $0.status != .skip }.count }

    func refresh(settings: AppSettings) async {
        isLoading = true
        errorMessage = nil
        // Phase 0: local dashboard immediately (no network).
        reloadLocalDashboard(settings: settings)

        defer {
            isLoading = false
            lastRefreshed = .now
            activity = activityStore.recent
            reloadLocalDashboard(settings: settings)
        }

        // Phase 1: live metadata + notify (background-friendly).
        LiveFollowStore.shared.refreshMetadata(for: nil, forceStatus: true)
        LiveOpenNotifyService.evaluate(settings: settings)

        // Phase 2: service health
        await health.probeAll()
        healthItems = health.items
        let fails = healthItems.filter { $0.status == .fail }
        if !fails.isEmpty {
            activityStore.log(.make(
                title: "服务探测",
                subtitle: "\(fails.count) 项异常：\(fails.prefix(2).map(\.title).joined(separator: "、"))",
                systemImage: "heart.text.square",
                tintHex: 0xFF453A,
                route: "health"
            ))
        }

        // Phase 3: check-in
        if settings.isCheckinConfigured {
            do {
                var base = settings.checkinBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                while base.hasSuffix("/") { base.removeLast() }
                let token = settings.checkinAPIToken
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\u{00a0}", with: "")
                checkinSummary = try await checkin.summary(baseURL: base, apiToken: token)
                CheckinHistoryStore.shared.record(from: checkinSummary)
                if let c = checkinSummary?.counts {
                    activityStore.log(.make(
                        title: "签到状态已更新",
                        subtitle: "正常 \(c.healthyValue)/\(c.totalValue) · 失败 \(c.failedValue)",
                        systemImage: "checkmark.seal.fill",
                        tintHex: c.failedValue > 0 ? 0xFF9F0A : 0x30D158,
                        route: "checkin"
                    ))
                }
                SmartNotifyService.evaluate(settings: settings, checkin: checkinSummary)
            } catch {
                errorMessage = (error as? NetworkError)?.errorDescription ?? error.localizedDescription
                activityStore.log(.make(
                    title: "签到同步失败",
                    subtitle: errorMessage ?? "",
                    systemImage: "exclamationmark.triangle",
                    tintHex: 0xFF453A,
                    route: "checkin"
                ))
            }
        } else {
            checkinSummary = nil
            SmartNotifyService.evaluate(settings: settings, checkin: nil)
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        reloadLocalDashboard(settings: settings)
        activity = activityStore.recent
    }

    private func reloadLocalDashboard(settings: AppSettings) {
        let live = LiveFollowStore.shared.items.filter { $0.isLive == true }
        liveNowCount = live.count
        liveNowNames = live.map(\.displayName)
        subsDueSoon = SubscriptionStore.shared.dueSoon
        watchLaterCount = WatchLaterStore.shared.items.count
    }

    var setupChecklist: [(String, Bool, OverviewDestination)] {
        [
            ("签到服务", AppSettings.shared.isCheckinConfigured, .checkinSettings),
            ("Sub2 监控", AppSettings.shared.isAdminConfigured, .settingsTab),
            ("Cloudflare", AppSettings.shared.isCloudflareConfigured, .settingsTab),
            ("笔记同步", AppSettings.shared.isFastNoteConfigured, .settingsTab)
        ]
    }
}

// MARK: - Home

struct OverviewHomeView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel = OverviewViewModel()
    @State private var path = NavigationPath()
    @State private var moduleQuery = ""

    private struct ModuleSearchItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let keywords: String
        let destination: OverviewViewModel.OverviewDestination
    }

    private var accent: Color { Color.accentColor }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular || AdaptiveLayout.isPad
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppleTheme.space5) {
                    heroHeader
                    FloatingSearchBar(text: $moduleQuery, placeholder: "搜索并打开模块…")
                    if moduleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        todayPulseStrip
                        onboardingSection
                        todayTodosSection
                        attentionSection
                        todayStrip
                        servicesQuickGrid
                        moreToolsRow
                        if let err = viewModel.errorMessage, !err.isEmpty {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    } else {
                        moduleSearchResults
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
                .adaptiveReadableWidth(AdaptiveLayout.contentMaxWidth)
            }
            .background(AppSurfaceBackground(accent: accent))
            .navigationTitle("总览")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh(settings: settings) }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("刷新总览")
                }
            }
            .refreshable {
                await viewModel.refresh(settings: settings)
            }
            .task {
                _ = await LocalNotifier.ensureAuthorized()
                await viewModel.refresh(settings: settings)
            }
            .onReceive(NotificationCenter.default.publisher(for: ForegroundNotificationDelegate.routeNotification)) { note in
                if let route = note.userInfo?["route"] as? String {
                    navigateActivity(route)
                }
            }
            .navigationDestination(for: OverviewViewModel.OverviewDestination.self) { dest in
                destinationView(dest)
            }
        }
    }

    // MARK: - Global module search

    private var moduleSearchItems: [ModuleSearchItem] {
        [
            .init(id: "express", title: "快递助手", subtitle: "多平台聚合、物流跟踪与云雀", systemImage: "shippingbox.fill", keywords: "快递 物流 包裹 京东 淘宝 菜鸟 拼多多 小米 云雀", destination: .expressAssistant),
            .init(id: "download", title: "视频下载", subtitle: "YouTube、抖音与 B 站", systemImage: "arrow.down.circle.fill", keywords: "下载 视频 youtube 油管 抖音 bilibili b站", destination: .download),
            .init(id: "live", title: "直播", subtitle: "多平台直播、关注与搜索", systemImage: "play.tv.fill", keywords: "直播 主播 虎牙 斗鱼 抖音 快手 bilibili", destination: .liveTab),
            .init(id: "music", title: "音乐", subtitle: "音乐库、播放与歌词", systemImage: "music.note", keywords: "音乐 歌曲 播放 歌词 navidrome", destination: .musicTab),
            .init(id: "checkin", title: "签到中心", subtitle: "GLaDOS、Emby 与签到状态", systemImage: "checkmark.seal.fill", keywords: "签到 glados emby", destination: .checkin),
            .init(id: "sub2", title: "Sub2 管理", subtitle: "账号调度、用户与分组", systemImage: "chart.bar.fill", keywords: "sub2 账号 用户 api key 分组 监控", destination: .sub2Monitor),
            .init(id: "cloudflare", title: "Cloudflare", subtitle: "域名、DNS 与用量", systemImage: "cloud.fill", keywords: "cloudflare cf 域名 dns 缓存", destination: .cloudflare),
            .init(id: "health", title: "服务健康", subtitle: "探测全部已配置服务", systemImage: "heart.text.square.fill", keywords: "服务 健康 探测 状态", destination: .serviceHealth),
            .init(id: "ip", title: "IP 检测", subtitle: "出口风险、流媒体与节点档案", systemImage: "network", keywords: "ip 检测 出口 风险 流媒体 节点", destination: .ipCheck),
            .init(id: "qr", title: "二维码助手", subtitle: "扫码、生成与安全规则", systemImage: "qrcode.viewfinder", keywords: "二维码 qr 扫码 生成", destination: .qrAssistant),
            .init(id: "translator", title: "翻译器", subtitle: "多语言文本翻译", systemImage: "character.book.closed.fill", keywords: "翻译 translator 语言", destination: .translator),
            .init(id: "market", title: "行情", subtitle: "油价、汇率与金价", systemImage: "chart.line.uptrend.xyaxis", keywords: "行情 油价 汇率 金价 黄金", destination: .market),
            .init(id: "novel", title: "小说阅读", subtitle: "书源、搜索与阅读器", systemImage: "books.vertical.fill", keywords: "小说 阅读 书源 legado txt", destination: .novel),
            .init(id: "telegram", title: "TG 片库", subtitle: "Telegram 频道视频", systemImage: "paperplane.fill", keywords: "telegram tg 片库 频道 视频", destination: .telegramChannel),
            .init(id: "sublink", title: "SublinkX", subtitle: "订阅与节点管理", systemImage: "link", keywords: "sublink 订阅 节点 clash v2ray surge", destination: .sublink),
            .init(id: "notes", title: "笔记同步", subtitle: "Fast Note 与 Markdown", systemImage: "note.text", keywords: "笔记 note markdown 同步", destination: .notes),
            .init(id: "reminders", title: "提醒", subtitle: "本地提醒事项", systemImage: "bell.fill", keywords: "提醒 待办 todo", destination: .reminders),
            .init(id: "subscriptions", title: "订阅账单", subtitle: "订阅到期与费用", systemImage: "creditcard.fill", keywords: "订阅 账单 到期 费用", destination: .subscriptions),
            .init(id: "control", title: "控制中心", subtitle: "通知、开播提醒与剪贴板", systemImage: "switch.2", keywords: "控制 中心 通知 剪贴板", destination: .controlCenter)
        ]
    }

    private var filteredModuleSearchItems: [ModuleSearchItem] {
        let terms = moduleQuery.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }
        return moduleSearchItems.filter { item in
            let haystack = "\(item.title) \(item.subtitle) \(item.keywords)".lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }

    @ViewBuilder
    private var moduleSearchResults: some View {
        if filteredModuleSearchItems.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "没有匹配模块",
                message: "没有找到「\(moduleQuery)」相关功能。",
                pathHint: "试试模块名称、平台名或用途",
                actionTitle: "清空搜索",
                action: { moduleQuery = "" }
            )
            .frame(minHeight: 320)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                AppSectionTitle(title: "搜索结果", systemImage: "magnifyingglass")
                ForEach(filteredModuleSearchItems) { item in
                    Button {
                        moduleQuery = ""
                        navigate(item.destination)
                    } label: {
                        AppNavRow(title: item.title, subtitle: item.subtitle, systemImage: item.systemImage, tint: .accentColor)
                            .appCard()
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98))
                }
            }
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(viewModel.greeting)")
                .font(.system(size: 28, weight: .bold))
            Text(viewModel.dateLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.headlineStatus)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(viewModel.attentionItems.isEmpty ? Color(hex: 0x30D158) : Color(hex: 0xFF9F0A))
            if let t = viewModel.lastRefreshed {
                Text("更新于 \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Today todos

    private var todayTodos: [(title: String, subtitle: String, dest: OverviewViewModel.OverviewDestination, tint: Color)] {
        var list: [(String, String, OverviewViewModel.OverviewDestination, Color)] = []
        if let fails = viewModel.checkinSummary?.projects?.filter({ $0.statusKind == .failed }), !fails.isEmpty {
            list.append((
                "签到失败 \(fails.count) 项",
                fails.prefix(2).map(\.displayTitle).joined(separator: "、"),
                .checkin,
                Color(hex: 0xFF453A)
            ))
        }
        let due = SubscriptionStore.shared.items.filter { $0.daysUntilDue >= 0 && $0.daysUntilDue <= 7 }
        if let first = due.sorted(by: { $0.daysUntilDue < $1.daysUntilDue }).first {
            list.append((
                "订阅到期",
                "\(first.name) · \(first.daysUntilDue) 天",
                .subscriptions,
                Color(hex: 0xFF9F0A)
            ))
        }
        let rem = ReminderStore.shared.items.filter { $0.daysLeft >= 0 && $0.daysLeft <= 3 }
        if let r = rem.first {
            list.append((
                "提醒",
                "\(r.title) · \(r.daysLeft) 天",
                .reminders,
                Color(hex: 0x64D2FF)
            ))
        }
        return list
    }

    @ViewBuilder
    private var todayTodosSection: some View {
        let todos = todayTodos
        if !todos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                AppSectionTitle(title: "今日待办", systemImage: "sun.max.fill")
                VStack(spacing: 8) {
                    ForEach(Array(todos.enumerated()), id: \.offset) { _, item in
                        Button {
                            navigate(item.dest)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(item.tint)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.98))
                    }
                }
            }
        }
    }

    // MARK: - Onboarding checklist

    @ViewBuilder
    private var onboardingSection: some View {
        let items = viewModel.setupChecklist
        let ready = items.filter(\.1).count
        if ready < items.count {
            VStack(alignment: .leading, spacing: 10) {
                AppSectionTitle(title: "开始配置", systemImage: "checklist")
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, row in
                        Button {
                            navigate(row.2)
                        } label: {
                            HStack {
                                Image(systemName: row.1 ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(row.1 ? Color(hex: 0x30D158) : .secondary)
                                Text(row.0)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if !row.1 {
                                    Text("去设置")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Today pulse (live / bills / komari / watch later)

    private var todayPulseStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: "今日速览", systemImage: "sparkles")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    pulseChip(
                        title: "直播中",
                        value: "\(viewModel.liveNowCount)",
                        caption: viewModel.liveNowCount > 0 ? viewModel.liveNowNames.first ?? "关注主播" : "暂无",
                        tint: Color(hex: 0xFF375F),
                        systemImage: "play.tv.fill"
                    ) { navigate(.liveTab) }

                    pulseChip(
                        title: "账单",
                        value: "\(viewModel.subsDueSoon.count)",
                        caption: viewModel.subsDueSoon.first.map { "\($0.daysUntilDue) 天内" } ?? "14 天内到期",
                        tint: Color(hex: 0xFF9F0A),
                        systemImage: "creditcard.fill"
                    ) {
                        // Prefer sheet with focus when due soon.
                        if let id = viewModel.subsDueSoon.first?.id {
                            AppDeepLinkStore.shared.presentSheet = .subscriptions
                            // Store focus for list highlight
                            UserDefaults.standard.set(id, forKey: "subscription.focusId")
                        } else {
                            navigate(.subscriptions)
                        }
                    }

                    pulseChip(
                        title: "控制中心",
                        value: "通知",
                        caption: "开播 / 剪贴板",
                        tint: Color.accentColor,
                        systemImage: "switch.2"
                    ) { navigate(.controlCenter) }
                }
            }
        }
    }

    private func pulseChip(
        title: String,
        value: String,
        caption: String,
        tint: Color,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(tint.brandGradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Spacer(minLength: 0)
                }
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 132, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }

    // MARK: - Attention

    @ViewBuilder
    private var attentionSection: some View {
        if viewModel.attentionItems.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color(hex: 0x30D158))
                Text("暂无需要处理的事项")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(14)
            .background(Color(hex: 0x30D158).opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(hex: 0x30D158).opacity(0.25), lineWidth: 1)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                AppSectionTitle(title: "需关注", systemImage: "bell.badge.fill")
                ForEach(viewModel.attentionItems) { item in
                    Button {
                        navigate(item.destination)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.systemImage)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(item.tint)
                                .frame(width: 36, height: 36)
                                .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .appCard()
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98))
                }
            }
        }
    }

    // MARK: - Today strip (service-first metrics)

    private var todayStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: "服务速览", systemImage: "square.grid.2x2.fill")
            LazyVGrid(
                columns: AdaptiveLayout.columns(minimum: AdaptiveLayout.metricMinTile, spacing: 12),
                spacing: 12
            ) {
                metricCard(
                    title: "签到",
                    value: viewModel.checkinTotal > 0
                        ? "\(viewModel.checkinHealthy)/\(viewModel.checkinTotal)"
                        : (settings.isCheckinConfigured ? "—" : "未配置"),
                    caption: viewModel.checkinProjects > 0
                        ? "\(viewModel.checkinProjects) 个项目 · 失败 \(viewModel.checkinFailed)"
                        : "每日状态",
                    tint: ServiceBrand.checkin.tint,
                    systemImage: "checkmark.seal.fill"
                ) {
                    navigate(settings.isCheckinConfigured ? .checkin : .checkinSettings)
                }

                metricCard(
                    title: "服务健康",
                    value: viewModel.healthConfigured > 0
                        ? "\(viewModel.healthOK)/\(viewModel.healthConfigured)"
                        : "—",
                    caption: viewModel.healthFail > 0 ? "\(viewModel.healthFail) 项异常" : "连通性探测",
                    tint: ServiceBrand.health.tint,
                    systemImage: "heart.text.square.fill"
                ) {
                    navigate(.serviceHealth)
                }

                metricCard(
                    title: "Sub2 管理",
                    value: settings.isAdminConfigured ? "已配置" : "未配置",
                    caption: "账号调度 · 用户余额",
                    tint: ServiceBrand.sub2.tint,
                    systemImage: "chart.bar.fill"
                ) {
                    navigate(.sub2Monitor)
                }

                metricCard(
                    title: "Cloudflare",
                    value: settings.isCloudflareConfigured ? "已配置" : "未配置",
                    caption: "用量 · 域名 · DNS",
                    tint: ServiceBrand.cloudflare.tint,
                    systemImage: "cloud.fill"
                ) {
                    navigate(.cloudflare)
                }
            }
        }
    }

    private func metricCard(
        title: String,
        value: String,
        caption: String,
        tint: Color,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(tint.brandGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                }
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
            .modifier(AppShadow.mid())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    // MARK: - Service-first quick grid

    private var servicesQuickGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: "常用服务", systemImage: "star.fill")
            LazyVGrid(
                columns: AdaptiveLayout.columns(
                    minimum: isRegularWidth ? 120 : AdaptiveLayout.quickTileMin,
                    spacing: 12
                ),
                spacing: 12
            ) {
                quickTile(brand: .checkin, title: "签到中心") { navigate(.checkin) }
                quickTile(brand: .sub2, title: "Sub2 管理") { navigate(.sub2Monitor) }
                quickTile(brand: .cloudflare, title: "Cloudflare") { navigate(.cloudflare) }
                quickTile(brand: .health, title: "服务健康") { navigate(.serviceHealth) }
                quickTile(brand: .ipCheck, title: "IP 检测") {
                    navigate(.ipCheck)
                }
                quickTile(brand: .translator, title: "笔记同步") {
                    navigate(.notes)
                }
                quickTile(brand: .habits, title: "提醒") {
                    navigate(.reminders)
                }
            }
        }
    }

    private func quickTile(brand: ServiceBrand, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ServiceBrandIcon(brand: brand, size: 44)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }

    private var moreToolsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: "更多", systemImage: "ellipsis.circle")
            Button {
                selectedTab = .services
            } label: {
                AppNavRow(
                    title: "全部服务与工具",
                    subtitle: "生活 · 资讯 · 下载 · 直播入口",
                    systemImage: "square.grid.2x2.fill",
                    tint: .accentColor
                )
                .appCard()
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))

            Button {
                navigate(.controlCenter)
            } label: {
                AppNavRow(
                    title: "控制中心",
                    subtitle: "通知 · 开播提醒 · 剪贴板智能条",
                    systemImage: "switch.2",
                    tint: .accentColor
                )
                .appCard()
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))

            Button {
                navigate(.proxyPack)
            } label: {
                AppNavRow(
                    title: "代理 / 节点探测包",
                    subtitle: "出口 IP · 流媒体 · 延迟档案",
                    systemImage: "network.badge.shield.half.filled",
                    tint: Color(hex: 0x0A84FF)
                )
                .appCard()
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))

            Button {
                selectedTab = .live
            } label: {
                AppNavRow(
                    title: "直播",
                    subtitle: "多平台关注与搜索",
                    brand: .live
                )
                .appCard()
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))
        }
    }

    // MARK: - Navigation

    private func navigate(_ dest: OverviewViewModel.OverviewDestination) {
        switch dest {
        case .servicesTab:
            selectedTab = .services
        case .liveTab:
            selectedTab = .live
        case .musicTab:
            selectedTab = .music
        case .settingsTab, .checkinSettings:
            selectedTab = .settings
        default:
            path.append(dest)
        }
    }

    private func navigateActivity(_ route: String) {
        switch route {
        case "checkin": navigate(.checkin)
        case "health": navigate(.serviceHealth)
        case "download": navigate(.download)
        case "subscription": navigate(.subscriptions)
        case "reminder": navigate(.reminders)
        case "notes": navigate(.notes)
        case "live": navigate(.liveTab)
        case "proxy": navigate(.proxyPack)
        case "settings": selectedTab = .settings
        default: break
        }
    }

    @ViewBuilder
    private func destinationView(_ dest: OverviewViewModel.OverviewDestination) -> some View {
        switch dest {
        case .checkin:
            CheckinHomeView()
        case .serviceHealth:
            ServiceHealthHomeView()
        case .download:
            DownloadHomeView(isTabSelected: true)
        case .sub2Monitor:
            MonitorHomeView()
        case .cloudflare:
            CloudflareHomeView()
        case .ipCheck:
            IPCheckHomeView()
        case .notes:
            FastNoteHomeView()
        case .reminders:
            ReminderHomeView()
        case .subscriptions:
            SubscriptionHomeView()
        case .controlCenter:
            ControlCenterView()
        case .proxyPack:
            ProxyNodePackView()
        case .watchLater:
            WatchLaterHomeView()
        case .expressAssistant:
            ExpressAssistantRootView()
        case .qrAssistant:
            QRAssistantHomeView()
        case .translator:
            TranslatorHomeView()
        case .market:
            MarketQuotesHomeView()
        case .novel:
            NovelRootView()
        case .telegramChannel:
            TGChannelRootView().environmentObject(settings)
        case .sublink:
            SublinkHomeView()
        case .servicesTab, .liveTab, .musicTab, .settingsTab, .checkinSettings:
            EmptyView()
        }
    }

    private func hostShort(_ baseURL: String) -> String {
        let t = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), let h = u.host, !h.isEmpty else {
            return t.isEmpty ? "未配置" : t
        }
        return h
    }
}
