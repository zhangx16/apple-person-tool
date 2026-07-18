import SwiftUI

/// Sub2API admin monitor — inspired by sub2api-mobile monitor tab.
struct MonitorHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = MonitorViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !settings.isAdminConfigured {
                        EmptyStateView(
                            symbol: "chart.bar.doc.horizontal",
                            title: "需要 Admin Token",
                            message: "在设置中填写 Sub2API Base URL 与 Admin API Key（x-api-key），即可查看仪表盘与账号状态。"
                        )
                        .padding(.top, 40)
                    } else {
                        rangePicker
                        if let err = viewModel.errorMessage {
                            errorBanner(err)
                        }
                        statsGrid
                        trendSection
                        modelsSection
                        accountsSection
                    }
                }
                .padding(16)
            }
            .background(AppleTheme.canvas)
            .navigationTitle("监控")
            .refreshable {
                await viewModel.load(settings: settings)
            }
            .task {
                await viewModel.load(settings: settings)
            }
            .onChange(of: viewModel.range) { _, _ in
                Task { await viewModel.load(settings: settings) }
            }
        }
    }

    private var rangePicker: some View {
        Picker("范围", selection: $viewModel.range) {
            ForEach(MonitorRange.allCases) { r in
                Text(r.label).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("统计时间范围")
    }

    private var statsGrid: some View {
        let s = viewModel.stats
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("今日请求", value: formatInt(s?.todayRequests), tint: .blue)
            statCard("今日费用", value: formatMoney(s?.todayCost), tint: .orange)
            statCard("今日 Token", value: formatCompact(s?.todayTokens), tint: .purple)
            statCard("RPM", value: formatDouble(s?.rpm), tint: .green)
            statCard("账号", value: "\(s?.normalAccounts ?? 0)/\(s?.totalAccounts ?? 0)", tint: .teal)
            statCard("异常账号", value: formatInt(s?.errorAccounts), tint: .red)
            statCard("API Keys", value: formatInt(s?.activeApiKeys), tint: .indigo)
            statCard("用户", value: formatInt(s?.totalUsers), tint: .secondary)
        }
    }

    private func statCard(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("请求趋势")
                .font(.headline)
            if viewModel.trend.isEmpty {
                Text("暂无趋势数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
            Text("模型用量 Top")
                .font(.headline)
            if viewModel.models.isEmpty {
                Text("暂无模型数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.models.prefix(8)) { m in
                    HStack {
                        Text(m.model)
                            .font(.subheadline)
                            .lineLimit(1)
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

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("上游账号")
                .font(.headline)
            if viewModel.accounts.isEmpty {
                Text("暂无账号")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.accounts.prefix(20)) { acc in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(acc.hasError ? Color.red : Color.green)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(acc.name ?? "#\(acc.id)")
                                .font(.subheadline.weight(.medium))
                            Text("\(acc.platform ?? "-") · \(acc.status ?? "-")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let err = acc.errorMessage, !err.isEmpty {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(acc.name ?? "账号") \(acc.hasError ? "异常" : "正常")")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
