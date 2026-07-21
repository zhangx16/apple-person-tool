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
        case monitor
        case komari
        case ipCheck
        case servicesTab
        case liveTab
        case settingsTab
        case checkinSettings
    }

    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var checkinSummary: CheckinSummary?
    @Published private(set) var healthItems: [ServiceHealthItem] = []
    @Published private(set) var lastRefreshed: Date?

    private let checkin = CheckinService.shared
    private let health = ServiceHealthService.shared

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
        let fail = attentionItems.count
        if fail == 0 {
            let healthy = checkinSummary?.counts?.healthyValue
            let total = checkinSummary?.counts?.totalValue
            if let healthy, let total, total > 0 {
                return "签到 \(healthy)/\(total) 正常 · 服务运行平稳"
            }
            return "一切顺利 · 从下方进入常用服务"
        }
        return "\(fail) 项需关注 · 点卡片处理"
    }

    var attentionItems: [AttentionItem] {
        var list: [AttentionItem] = []

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
        defer {
            isLoading = false
            lastRefreshed = .now
        }

        // Parallel-ish: health then checkin (health is sequential internally).
        await health.probeAll()
        healthItems = health.items

        if settings.isCheckinConfigured {
            do {
                var base = settings.checkinBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                while base.hasSuffix("/") { base.removeLast() }
                let token = settings.checkinAPIToken
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\u{00a0}", with: "")
                checkinSummary = try await checkin.summary(baseURL: base, apiToken: token)
            } catch {
                // Don't block whole overview; surface soft error.
                errorMessage = (error as? NetworkError)?.errorDescription ?? error.localizedDescription
            }
        } else {
            checkinSummary = nil
        }
    }
}

// MARK: - Home

struct OverviewHomeView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = OverviewViewModel()
    @State private var path = NavigationPath()

    private var accent: Color { Color.accentColor }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppleTheme.space5) {
                    heroHeader
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
                }
                .padding(16)
                .padding(.bottom, 28)
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
                await viewModel.refresh(settings: settings)
            }
            .navigationDestination(for: OverviewViewModel.OverviewDestination.self) { dest in
                destinationView(dest)
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
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
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
                    title: "监控",
                    value: settings.isAdminConfigured ? "已配置" : "未配置",
                    caption: "Sub2 · Cloudflare",
                    tint: ServiceBrand.sub2.tint,
                    systemImage: "chart.bar.fill"
                ) {
                    navigate(.monitor)
                }

                metricCard(
                    title: "Komari",
                    value: settings.komariBaseURL.isEmpty ? "未配置" : "节点",
                    caption: hostShort(settings.komariBaseURL),
                    tint: ServiceBrand.komari.tint,
                    systemImage: "server.rack"
                ) {
                    navigate(.komari)
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
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                quickTile(brand: .checkin, title: "签到中心") { navigate(.checkin) }
                quickTile(brand: .sub2, title: "监控中心") { navigate(.monitor) }
                quickTile(brand: .komari, title: "Komari") { navigate(.komari) }
                quickTile(brand: .health, title: "服务健康") { navigate(.serviceHealth) }
                quickTile(brand: .cloudflare, title: "Cloudflare") {
                    path.append(OverviewViewModel.OverviewDestination.monitor)
                }
                quickTile(brand: .ipCheck, title: "IP 检测") {
                    navigate(.ipCheck)
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
        case .settingsTab, .checkinSettings:
            selectedTab = .settings
        default:
            path.append(dest)
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
        case .monitor:
            MonitorShellView()
        case .komari:
            KomariHomeView()
        case .ipCheck:
            IPCheckHomeView()
        case .servicesTab, .liveTab, .settingsTab, .checkinSettings:
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

