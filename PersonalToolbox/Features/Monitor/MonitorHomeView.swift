import SwiftUI

/// Sub2API admin console — aligned with [sub2api-mobile](https://github.com/ckken/sub2api-mobile).
struct MonitorHomeView: View {
    /// When true (MonitorShellView), hide principal title — shell menu owns it.
    var hidesChromeTitle: Bool = false

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = MonitorViewModel()

    @State private var balanceUser: AdminUser?
    @State private var keysUser: AdminUser?
    @State private var loadedKeys: [AdminApiKey] = []
    @State private var isLoadingKeys = false
    @State private var detailAccount: AdminAccount?

    var body: some View {
        Group {
            if !settings.isAdminConfigured {
                EmptyStateView(
                    symbol: "chart.bar.doc.horizontal",
                    title: "需要 Admin Token",
                    message: "填写 Sub2API Base URL 与 Admin API Key（x-api-key），即可管理账号调度、用户余额与分组。",
                    pathHint: "设置 → Sub2API 监控"
                )
                .padding(.top, 40)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    Picker("分区", selection: $viewModel.pane) {
                        ForEach(MonitorPane.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    content
                }
            }
        }
        .background(AppSurfaceBackground(accent: Color.accentColor))
        .navigationTitle(hidesChromeTitle ? "" : "Sub2 管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !hidesChromeTitle {
                ToolbarItem(placement: .principal) {
                    ServiceBrandTitle(brand: .sub2, title: "Sub2 管理")
                }
            }
        }
        .refreshable { await viewModel.load(settings: settings) }
        .task { await viewModel.load(settings: settings) }
        .onChange(of: viewModel.range) { _, _ in
            Task { await viewModel.load(settings: settings) }
        }
        .overlay(alignment: .bottom) {
            bannerStack
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .sheet(item: $balanceUser) { user in
            BalanceSheet(user: user, isBusy: viewModel.isMutating) { amount, op, notes in
                let ok = await viewModel.adjustBalance(
                    settings: settings,
                    user: user,
                    amount: amount,
                    operation: op,
                    notes: notes
                )
                if ok { balanceUser = nil }
                return ok
            }
        }
        .sheet(item: $keysUser) { user in
            NavigationStack {
                List {
                    if isLoadingKeys {
                        ProgressView("加载 API Keys…")
                    } else if loadedKeys.isEmpty {
                        Text("暂无 API Key").foregroundStyle(.secondary)
                    } else {
                        ForEach(loadedKeys) { k in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(k.displayName).font(.subheadline.weight(.semibold))
                                Text(k.maskedKey).font(.caption.monospaced())
                                HStack {
                                    Text(k.status ?? "—")
                                        .font(.caption2)
                                    Spacer()
                                    if let used = k.quotaUsed, let q = k.quota {
                                        Text(String(format: "额度 %.0f / %.0f", used, q))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .navigationTitle(user.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { keysUser = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $detailAccount) { acc in
            AccountDetailSheet(
                account: acc,
                today: viewModel.accountTodayStats[acc.id],
                isBusy: viewModel.isMutating,
                onTest: {
                    await viewModel.testAccount(settings: settings, account: acc)
                },
                onRefresh: {
                    await viewModel.refreshAccount(settings: settings, account: acc)
                },
                onToggleSchedulable: {
                    await viewModel.toggleSchedulable(settings: settings, account: acc)
                },
                onLoadToday: {
                    await viewModel.loadTodayStats(settings: settings, accountId: acc.id)
                }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.pane {
        case .overview:
            ScrollView {
                overviewBody
                    .padding(16)
            }
        case .accounts:
            accountsList
        case .users:
            usersList
        case .groups:
            groupsList
        }
    }

    // MARK: - Overview

    private var overviewBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("范围", selection: $viewModel.range) {
                ForEach(MonitorRange.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.isLoading && viewModel.stats == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity)
            }

            let s = viewModel.stats
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard("今日请求", value: formatInt(s?.todayRequests), tint: .blue)
                statCard("今日费用", value: formatMoney(s?.todayCost), tint: .orange)
                statCard("今日 Token", value: formatCompact(s?.todayTokens), tint: .purple)
                statCard("RPM", value: formatDouble(s?.rpm), tint: .green)
                statCard("账号", value: "\(s?.normalAccounts ?? 0)/\(s?.totalAccounts ?? 0)", tint: .teal)
                statCard("异常账号", value: formatInt(s?.errorAccounts), tint: .red)
                statCard("API Keys", value: formatInt(s?.activeApiKeys), tint: .indigo)
                statCard("用户", value: formatInt(s?.totalUsers), tint: .secondary)
            }

            trendSection
            modelsSection

            if let last = viewModel.lastUpdated {
                Text("更新于 \(last.formatted(date: .omitted, time: .shortened)) · 对齐 sub2api-mobile")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func statCard(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("请求趋势").font(.headline)
            if viewModel.trend.isEmpty {
                Text("暂无趋势数据").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.trend.suffix(8).reversed()) { point in
                    HStack {
                        Text(shortDate(point.date))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        ProgressView(value: Double(point.requests ?? 0), total: maxTrend)
                            .tint(.accentColor)
                        Text("\(point.requests ?? 0)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private var maxTrend: Double {
        max(1, Double(viewModel.trend.map { $0.requests ?? 0 }.max() ?? 1))
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型用量 Top").font(.headline)
            if viewModel.models.isEmpty {
                Text("暂无模型数据").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.models.prefix(8)) { m in
                    HStack {
                        Text(m.model).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text("\(m.requests ?? 0) 次")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(formatMoney(m.cost))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    // MARK: - Accounts

    private var accountsList: some View {
        List {
            Section {
                TextField("搜索账号 / 平台 / 状态", text: $viewModel.accountSearch)
                    .textInputAutocapitalization(.never)
            }
            Section {
                if viewModel.filteredAccounts.isEmpty {
                    Text(viewModel.accounts.isEmpty ? "暂无上游账号" : "无匹配账号")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.filteredAccounts) { acc in
                        Button {
                            detailAccount = acc
                            Task { await viewModel.loadTodayStats(settings: settings, accountId: acc.id) }
                        } label: {
                            accountRow(acc)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task { await viewModel.toggleSchedulable(settings: settings, account: acc) }
                            } label: {
                                Label(
                                    (acc.schedulable ?? true) ? "停调度" : "开调度",
                                    systemImage: (acc.schedulable ?? true) ? "pause.circle" : "play.circle"
                                )
                            }
                            .tint((acc.schedulable ?? true) ? .orange : .green)

                            Button {
                                Task { await viewModel.testAccount(settings: settings, account: acc) }
                            } label: {
                                Label("测试", systemImage: "bolt.horizontal.circle")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await viewModel.refreshAccount(settings: settings, account: acc) }
                            } label: {
                                Label("刷新", systemImage: "arrow.clockwise")
                            }
                            .tint(.indigo)
                        }
                    }
                }
            } header: {
                Text("上游账号 \(viewModel.filteredAccounts.count)")
            } footer: {
                Text("左滑：停/开调度、测试连通；右滑：刷新凭据。点进详情可看今日用量。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func accountRow(_ acc: AdminAccount) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(acc.hasError ? Color.red : ((acc.schedulable ?? true) ? Color.green : Color.orange))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(acc.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(acc.platform ?? "-") · \(acc.type ?? "-") · \(acc.status ?? "-")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let s = acc.schedulable {
                        Text(s ? "可调度" : "已暂停")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((s ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    }
                    if let cur = acc.currentConcurrency, let max = acc.concurrency {
                        Text("并发 \(cur)/\(max)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let err = acc.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Users

    private var usersList: some View {
        List {
            Section {
                TextField("搜索邮箱 / 用户名", text: $viewModel.userSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                if viewModel.filteredUsers.isEmpty {
                    Text(viewModel.users.isEmpty ? "暂无用户" : "无匹配用户")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.filteredUsers) { user in
                        userRow(user)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    balanceUser = user
                                } label: {
                                    Label("余额", systemImage: "yensign.circle")
                                }
                                .tint(.orange)

                                Button {
                                    Task {
                                        keysUser = user
                                        isLoadingKeys = true
                                        loadedKeys = await viewModel.loadUserApiKeys(settings: settings, userId: user.id)
                                        isLoadingKeys = false
                                    }
                                } label: {
                                    Label("Keys", systemImage: "key")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task {
                                        await viewModel.setUserStatus(
                                            settings: settings,
                                            user: user,
                                            active: !user.isActive
                                        )
                                    }
                                } label: {
                                    Label(user.isActive ? "禁用" : "启用", systemImage: user.isActive ? "person.fill.xmark" : "person.fill.checkmark")
                                }
                                .tint(user.isActive ? .red : .green)
                            }
                    }
                }
            } header: {
                Text("用户 \(viewModel.filteredUsers.count)")
            } footer: {
                Text("左滑调余额 / 看 Keys；右滑启用或禁用。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func userRow(_ user: AdminUser) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(user.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName)
                    .font(.subheadline.weight(.semibold))
                if let email = user.email, email != user.displayName {
                    Text(email).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Text(String(format: "余额 $%.2f", user.balance ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                    Text(user.role ?? "user")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(user.status ?? "—")
                        .font(.caption2)
                        .foregroundStyle(user.isActive ? Color.secondary : Color.red)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Groups

    private var groupsList: some View {
        List {
            Section {
                TextField("搜索分组", text: $viewModel.groupSearch)
                    .textInputAutocapitalization(.never)
            }
            Section {
                if viewModel.filteredGroups.isEmpty {
                    Text(viewModel.groups.isEmpty ? "暂无分组" : "无匹配分组")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.filteredGroups) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(g.platform ?? "-") · 账号 \(g.accountCount ?? 0) · 倍率 \(g.rateMultiplier.map { String(format: "%.2f", $0) } ?? "—")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let d = g.description, !d.isEmpty {
                                Text(d).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                            }
                            HStack(spacing: 8) {
                                if let v = g.dailyLimitUsd {
                                    Text(String(format: "日限 $%.0f", v)).font(.caption2)
                                }
                                if let v = g.monthlyLimitUsd {
                                    Text(String(format: "月限 $%.0f", v)).font(.caption2)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("分组 \(viewModel.filteredGroups.count)")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Banners / format

    @ViewBuilder
    private var bannerStack: some View {
        VStack(spacing: 8) {
            if let err = viewModel.errorMessage {
                toast(err, isError: true) { viewModel.errorMessage = nil }
            }
            if let status = viewModel.statusMessage {
                toast(status, isError: false) { viewModel.statusMessage = nil }
                    .task(id: status) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        if viewModel.statusMessage == status { viewModel.statusMessage = nil }
                    }
            }
        }
    }

    private func toast(_ text: String, isError: Bool, dismiss: @escaping () -> Void) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isError ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            (isError ? Color.red.opacity(0.12) : Color.green.opacity(0.14)),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatInt(_ v: Int?) -> String {
        guard let v else { return "--" }
        return v.formatted()
    }

    private func formatDouble(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.1f", v)
    }

    private func formatMoney(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "$%.2f", v)
    }

    private func formatCompact(_ v: Int?) -> String {
        guard let v else { return "--" }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", Double(v) / 1_000) }
        return "\(v)"
    }

    private func shortDate(_ s: String) -> String {
        if s.count >= 16 { return String(s.dropFirst(5).prefix(11)) }
        if s.count >= 10 { return String(s.dropFirst(5)) }
        return s
    }
}

// MARK: - Balance sheet

private struct BalanceSheet: View {
    let user: AdminUser
    let isBusy: Bool
    let onSubmit: (Double, AdminBalanceOperation, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var operation: AdminBalanceOperation = .add
    @State private var notes = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("用户") {
                    Text(user.displayName)
                    Text(String(format: "当前余额 $%.4f", user.balance ?? 0))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Section("调整") {
                    Picker("操作", selection: $operation) {
                        ForEach(AdminBalanceOperation.allCases) { op in
                            Text(op.title).tag(op)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("备注（可选）", text: $notes)
                }
                if let localError {
                    Section { Text(localError).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("调整余额")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBusy {
                        ProgressView()
                    } else {
                        Button("提交") {
                            Task {
                                localError = nil
                                guard let amount = Double(amountText.trimmingCharacters(in: .whitespaces)),
                                      amount >= 0 else {
                                    localError = "请输入有效金额"
                                    return
                                }
                                _ = await onSubmit(amount, operation, notes)
                            }
                        }
                    }
                }
            }
            .disabled(isBusy)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Account detail

private struct AccountDetailSheet: View {
    let account: AdminAccount
    let today: AdminAccountTodayStats?
    let isBusy: Bool
    let onTest: () async -> Void
    let onRefresh: () async -> Void
    let onToggleSchedulable: () async -> Void
    let onLoadToday: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("账号") {
                    LabeledContent("名称", value: account.displayName)
                    LabeledContent("平台", value: account.platform ?? "—")
                    LabeledContent("类型", value: account.type ?? "—")
                    LabeledContent("状态", value: account.status ?? "—")
                    LabeledContent("调度", value: (account.schedulable ?? true) ? "可调度" : "已暂停")
                    if let cur = account.currentConcurrency, let max = account.concurrency {
                        LabeledContent("并发", value: "\(cur)/\(max)")
                    }
                    if let last = account.lastUsedAt {
                        LabeledContent("最近使用", value: last)
                    }
                }
                if let err = account.errorMessage, !err.isEmpty {
                    Section("错误") {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("今日用量") {
                    if let today {
                        LabeledContent("请求", value: "\(today.requests ?? 0)")
                        LabeledContent("Token", value: "\(today.tokens ?? 0)")
                        LabeledContent("费用", value: String(format: "$%.4f", today.cost ?? 0))
                    } else {
                        ProgressView("加载…")
                            .task { await onLoadToday() }
                    }
                }
                Section {
                    Button {
                        Task { await onToggleSchedulable() }
                    } label: {
                        Label(
                            (account.schedulable ?? true) ? "暂停调度" : "开启调度",
                            systemImage: (account.schedulable ?? true) ? "pause.circle" : "play.circle"
                        )
                    }
                    Button {
                        Task { await onTest() }
                    } label: {
                        Label("测试连通", systemImage: "bolt.horizontal.circle")
                    }
                    Button {
                        Task { await onRefresh() }
                    } label: {
                        Label("刷新凭据", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isBusy)
            }
            .navigationTitle(account.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay {
                if isBusy {
                    ProgressView().padding().background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }
}
