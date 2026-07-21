import SwiftUI

// MARK: - ViewModel

@MainActor
final class CheckinViewModel: ObservableObject {
    @Published private(set) var summary: CheckinSummary?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var search = ""
    @Published var filterStatus: CheckinStatusKind? = nil
    @Published private(set) var lastUpdated: Date?

    private let service = CheckinService.shared

    /// Prefer server-side merged projects; fall back to client-side merge from flat items.
    var projects: [CheckinProject] {
        if let list = summary?.projects, !list.isEmpty {
            return list
        }
        return Self.mergeItemsClientSide(summary?.items ?? [])
    }

    var filteredProjects: [CheckinProject] {
        var list = projects
        if let filterStatus {
            list = list.filter { project in
                project.statusKind == filterStatus
                    || project.accountList.contains { $0.statusKind == filterStatus }
            }
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { project in
                project.displayTitle.lowercased().contains(q)
                    || project.displaySubtitle.lowercased().contains(q)
                    || (project.message ?? "").lowercased().contains(q)
                    || (project.botUsername ?? "").lowercased().contains(q)
                    || project.accountList.contains {
                        $0.displayName.lowercased().contains(q)
                            || ($0.message ?? "").lowercased().contains(q)
                            || ($0.phone ?? "").lowercased().contains(q)
                    }
            }
        }
        return list
    }

    /// Sections: 网站签到 / Telegram Bot
    var sections: [(label: String, key: String, projects: [CheckinProject])] {
        var web: [CheckinProject] = []
        var tg: [CheckinProject] = []
        for p in filteredProjects {
            if p.isTelegram { tg.append(p) } else { web.append(p) }
        }
        var out: [(String, String, [CheckinProject])] = []
        if !web.isEmpty { out.append(("网站签到", "website", web)) }
        if !tg.isEmpty { out.append(("Telegram Bot", "telegram_bot", tg)) }
        return out
    }

    func load(settings: AppSettings) async {
        var base = settings.checkinBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let token = settings.checkinAPIToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: "")
        guard !base.isEmpty, !token.isEmpty else {
            errorMessage = "请先在「设置 → 签到服务」填写 Base URL 与 API Token"
            summary = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            summary = try await service.summary(baseURL: base, apiToken: token)
            lastUpdated = .now
            Haptics.success()
        } catch {
            errorMessage = Self.chineseError(error)
            Haptics.error()
        }
    }

    /// Fallback merge when older server has no `projects`.
    static func mergeItemsClientSide(_ items: [CheckinItem]) -> [CheckinProject] {
        var webOrder: [String] = []
        var webMap: [String: [CheckinItem]] = [:]
        var tgOrder: [String] = []
        var tgMap: [String: [CheckinItem]] = [:]

        for item in items {
            if item.kind == "telegram_bot" || item.provider == "telegram_bot" {
                let key = (item.botUsername ?? item.id).replacingOccurrences(of: "@", with: "")
                if tgMap[key] == nil {
                    tgOrder.append(key)
                    tgMap[key] = []
                }
                tgMap[key]?.append(item)
            } else {
                let key = item.provider ?? "unknown"
                if webMap[key] == nil {
                    webOrder.append(key)
                    webMap[key] = []
                }
                webMap[key]?.append(item)
            }
        }

        var projects: [CheckinProject] = []
        for key in webOrder {
            let accounts = webMap[key] ?? []
            projects.append(makeProject(
                id: "web:\(key)",
                kind: "website",
                provider: key,
                title: accounts.first?.displayProvider ?? key,
                subtitle: "\(accounts.count) 个账号",
                botUsername: nil,
                botName: nil,
                avatarURL: nil,
                accounts: accounts
            ))
        }
        for key in tgOrder {
            let accounts = tgMap[key] ?? []
            let botName = accounts.first?.botName ?? key
            projects.append(makeProject(
                id: "tg:\(key)",
                kind: "telegram_bot",
                provider: "telegram_bot",
                title: botName,
                subtitle: "@\(key)",
                botUsername: key,
                botName: botName,
                avatarURL: accounts.first?.avatarURL,
                accounts: accounts
            ))
        }
        return projects
    }

    private static func makeProject(
        id: String,
        kind: String,
        provider: String,
        title: String,
        subtitle: String,
        botUsername: String?,
        botName: String?,
        avatarURL: String?,
        accounts: [CheckinItem]
    ) -> CheckinProject {
        var counts = CheckinCounts(
            total: accounts.count,
            projectTotal: 1,
            success: 0, already: 0, failed: 0, skipped: 0, unknown: 0, pending: 0, healthy: 0
        )
        for a in accounts {
            switch a.statusKind {
            case .success: counts.success = (counts.success ?? 0) + 1
            case .already: counts.already = (counts.already ?? 0) + 1
            case .failed: counts.failed = (counts.failed ?? 0) + 1
            case .skipped: counts.skipped = (counts.skipped ?? 0) + 1
            case .pending: counts.pending = (counts.pending ?? 0) + 1
            case .unknown: counts.unknown = (counts.unknown ?? 0) + 1
            }
        }
        counts.healthy = (counts.success ?? 0) + (counts.already ?? 0)
        let status: String
        if (counts.failed ?? 0) > 0 { status = "failed" }
        else if accounts.allSatisfy({ $0.statusKind == .skipped }) { status = "skipped" }
        else if accounts.allSatisfy({ $0.statusKind == .already }) { status = "already" }
        else if accounts.allSatisfy({ $0.statusKind == .success || $0.statusKind == .already }) {
            status = "success"
        } else { status = "unknown" }

        let checkedAt = accounts.compactMap(\.checkedAt).max() ?? ""
        let healthy = counts.healthy ?? 0
        return CheckinProject(
            id: id,
            kind: kind,
            provider: provider,
            providerLabel: accounts.first?.providerLabel ?? provider,
            title: title,
            subtitle: subtitle,
            botUsername: botUsername,
            botName: botName,
            avatarURL: avatarURL,
            status: status,
            ok: status == "success" || status == "already",
            message: "\(accounts.count) 账号 · \(healthy) 正常 · \(counts.failed ?? 0) 失败",
            checkedAt: checkedAt,
            accountCount: accounts.count,
            counts: counts,
            accounts: accounts
        )
    }

    static func chineseError(_ error: Error) -> String {
        if let net = error as? NetworkError {
            return net.errorDescription ?? "网络错误"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "无网络连接"
            case NSURLErrorTimedOut: return "请求超时"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "无法连接服务器"
            default: break
            }
        }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "加载失败" : text
    }
}

// MARK: - Home

struct CheckinHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = CheckinViewModel()
    @State private var selected: CheckinProject?

    private var accent: Color { ServiceBrand.checkin.tint }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppleTheme.space5) {
                if !settings.isCheckinConfigured {
                    EmptyStateView(
                        symbol: "checkmark.seal",
                        title: "配置签到服务",
                        message: "填写 glados-checkin-web 的 Base URL 与 APP_API_TOKEN。",
                        pathHint: "设置 → 签到服务",
                        actionTitle: nil
                    )
                    .frame(minHeight: 280)
                } else {
                    overviewCard
                    filterChips
                    FloatingSearchBar(text: $viewModel.search, placeholder: "搜索项目、Bot、账号…")
                        .padding(.horizontal, 2)

                    if let err = viewModel.errorMessage {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if viewModel.isLoading && viewModel.summary == nil {
                        ProgressView("加载签到状态…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.sections.isEmpty {
                        EmptyStateView(
                            symbol: "tray",
                            title: viewModel.projects.isEmpty ? "暂无签到项" : "无匹配结果",
                            message: viewModel.projects.isEmpty
                                ? "服务端还没有账号或 Telegram 签到结果。"
                                : "试试其他关键词或筛选。",
                            actionTitle: viewModel.projects.isEmpty ? "重新加载" : "清除筛选",
                            action: {
                                if viewModel.projects.isEmpty {
                                    Task { await viewModel.load(settings: settings) }
                                } else {
                                    viewModel.search = ""
                                    viewModel.filterStatus = nil
                                }
                            }
                        )
                        .frame(minHeight: 240)
                    } else {
                        ForEach(viewModel.sections, id: \.key) { section in
                            projectSection(section.label, projects: section.projects)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(AppSurfaceBackground(accent: accent))
        .navigationTitle("签到中心")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .checkin, title: "签到中心")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.load(settings: settings) }
                } label: {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!settings.isCheckinConfigured || viewModel.isLoading)
                .accessibilityLabel("刷新")
            }
        }
        .refreshable {
            await viewModel.load(settings: settings)
        }
        .task {
            if settings.isCheckinConfigured {
                await viewModel.load(settings: settings)
            }
        }
        .navigationDestination(item: $selected) { project in
            CheckinProjectDetailView(project: project)
        }
    }

    // MARK: - Overview

    private var overviewCard: some View {
        let c = viewModel.summary?.counts
        let projectCount = viewModel.projects.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日总览")
                        .font(.headline)
                    Text("\(projectCount) 个签到项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let t = viewModel.lastUpdated {
                        Text("更新于 \(t.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                StatusPill(
                    title: "\(c?.healthyValue ?? 0)/\(c?.totalValue ?? 0) 账号正常",
                    color: (c?.failedValue ?? 0) > 0 ? Color(hex: 0xFF9F0A) : Color(hex: 0x30D158),
                    systemImage: "checkmark.seal.fill",
                    style: (c?.failedValue ?? 0) == 0 && (c?.totalValue ?? 0) > 0 ? .solid : .soft
                )
            }

            HStack(spacing: 8) {
                metric("成功", c?.successValue ?? 0, Color(hex: 0x30D158))
                metric("已签", c?.alreadyValue ?? 0, Color(hex: 0x64D2FF))
                metric("失败", c?.failedValue ?? 0, Color(hex: 0xFF453A))
                metric("跳过", c?.skippedValue ?? 0, Color(hex: 0xFF9F0A))
            }
        }
        .appCardV2()
    }

    private func metric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filters

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "全部",
                    systemImage: "square.grid.2x2",
                    isSelected: viewModel.filterStatus == nil,
                    tint: accent
                ) {
                    viewModel.filterStatus = nil
                }
                ForEach([CheckinStatusKind.failed, .success, .already, .skipped], id: \.rawValue) { kind in
                    FilterChip(
                        title: kind.title,
                        systemImage: kind.systemImage,
                        isSelected: viewModel.filterStatus == kind,
                        tint: kind.color
                    ) {
                        viewModel.filterStatus = viewModel.filterStatus == kind ? nil : kind
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private func projectSection(_ title: String, projects: [CheckinProject]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(
                title: title,
                systemImage: title.contains("Telegram") ? "paperplane.fill" : "globe"
            )
            VStack(spacing: 10) {
                ForEach(projects) { project in
                    Button {
                        selected = project
                    } label: {
                        CheckinProjectRow(project: project)
                            .appCard()
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98))
                }
            }
        }
    }
}

// MARK: - Avatar

struct CheckinAvatarView: View {
    var url: URL?
    var fallbackSystemImage: String
    var fallbackTint: Color
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .controlSize(.mini)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(fallbackTint.opacity(0.12), in: Circle())
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(AppStroke.highlight, lineWidth: 0.5)
        }
    }

    private var fallback: some View {
        Image(systemName: fallbackSystemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(fallbackTint)
    }
}

// MARK: - Project row

private struct CheckinProjectRow: View {
    let project: CheckinProject

    var body: some View {
        HStack(spacing: 12) {
            CheckinAvatarView(
                url: project.avatar,
                fallbackSystemImage: project.isTelegram ? "paperplane.fill" : "globe",
                fallbackTint: project.statusKind.color,
                size: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(project.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            StatusPill(
                title: project.statusKind.title,
                color: project.statusKind.color,
                systemImage: project.statusKind.systemImage
            )
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.displayTitle)，\(project.accountList.count) 个账号，\(project.statusKind.title)")
    }

    private var subtitle: String {
        var parts: [String] = []
        if !project.displaySubtitle.isEmpty {
            parts.append(project.displaySubtitle)
        }
        let n = project.accountCount ?? project.accountList.count
        parts.append("\(n) 账号")
        if let c = project.counts {
            if (c.failedValue) > 0 { parts.append("失败 \(c.failedValue)") }
            else if (c.skippedValue) > 0 { parts.append("跳过 \(c.skippedValue)") }
            else { parts.append("正常 \(c.healthyValue)") }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Project detail (merged accounts)

struct CheckinProjectDetailView: View {
    let project: CheckinProject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    CheckinAvatarView(
                        url: project.avatar,
                        fallbackSystemImage: project.isTelegram ? "paperplane.fill" : "globe",
                        fallbackTint: project.statusKind.color,
                        size: 64
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.displayTitle)
                            .font(.title3.weight(.bold))
                        if !project.displaySubtitle.isEmpty {
                            Text(project.displaySubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let msg = project.message, !msg.isEmpty {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    StatusPill(
                        title: project.statusKind.title,
                        color: project.statusKind.color,
                        systemImage: project.statusKind.systemImage,
                        style: project.statusKind == .failed ? .solid : .soft
                    )
                }
                .appCardV2()

                if let c = project.counts {
                    HStack(spacing: 8) {
                        miniStat("成功", c.successValue, Color(hex: 0x30D158))
                        miniStat("已签", c.alreadyValue, Color(hex: 0x64D2FF))
                        miniStat("失败", c.failedValue, Color(hex: 0xFF453A))
                        miniStat("跳过", c.skippedValue, Color(hex: 0xFF9F0A))
                    }
                }

                AppSectionTitle(
                    title: "账号 (\(project.accountList.count))",
                    systemImage: "person.2.fill"
                )
                VStack(spacing: 10) {
                    ForEach(project.accountList) { account in
                        accountCard(account)
                    }
                }
            }
            .padding(16)
        }
        .background(AppSurfaceBackground(accent: project.statusKind.color))
        .navigationTitle(project.isTelegram ? "Bot 签到" : "项目详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func miniStat(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func accountCard(_ account: CheckinItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(account.displayName)
                    .font(.body.weight(.semibold))
                Spacer()
                StatusPill(
                    title: account.statusKind.title,
                    color: account.statusKind.color,
                    systemImage: account.statusKind.systemImage
                )
            }
            if let msg = account.message, !msg.isEmpty {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let at = account.checkedAt, !at.isEmpty {
                Text(at)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            // Points / balance for website accounts
            HStack(spacing: 12) {
                if let d = account.pointsDelta {
                    let unit = account.currency.map { " \($0)" } ?? ""
                    let num = d == floor(d) ? "+\(Int(d))" : String(format: "+%.2f", d)
                    labelChip("变动", num + unit)
                }
                if let b = account.balance {
                    let unit = account.currency.map { " \($0)" } ?? ""
                    let num = b == floor(b) ? "\(Int(b))" : String(format: "%.2f", b)
                    labelChip("余额", num + unit)
                }
                if let s = account.streak {
                    labelChip("连续", s == floor(s) ? "\(Int(s)) 天" : String(format: "%.0f 天", s))
                }
                if let left = account.leftDays, !left.isEmpty {
                    labelChip("剩余", left)
                }
            }
        }
        .appCard()
    }

    private func labelChip(_ k: String, _ v: String) -> some View {
        Text("\(k) \(v)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}
