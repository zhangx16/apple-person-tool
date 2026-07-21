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

    var items: [CheckinItem] {
        summary?.items ?? []
    }

    var filteredItems: [CheckinItem] {
        var list = items
        if let filterStatus {
            list = list.filter { $0.statusKind == filterStatus }
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.displayName.lowercased().contains(q)
                    || $0.displayProvider.lowercased().contains(q)
                    || ($0.message ?? "").lowercased().contains(q)
                    || ($0.botUsername ?? "").lowercased().contains(q)
                    || ($0.provider ?? "").lowercased().contains(q)
            }
        }
        return list
    }

    /// Group filtered items by provider label for sectioned list.
    var sections: [(label: String, key: String, items: [CheckinItem])] {
        var order: [String] = []
        var map: [String: [CheckinItem]] = [:]
        for item in filteredItems {
            let key = item.provider ?? item.displayProvider
            if map[key] == nil {
                order.append(key)
                map[key] = []
            }
            map[key]?.append(item)
        }
        return order.compactMap { key in
            guard let items = map[key], !items.isEmpty else { return nil }
            let label = items.first?.displayProvider ?? key
            return (label, key, items)
        }
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
    @State private var selected: CheckinItem?

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
                    FloatingSearchBar(text: $viewModel.search, placeholder: "搜索账号、Bot、消息…")
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
                            title: viewModel.items.isEmpty ? "暂无签到项" : "无匹配结果",
                            message: viewModel.items.isEmpty
                                ? "服务端还没有账号或 Telegram 签到结果。"
                                : "试试其他关键词或筛选。",
                            actionTitle: viewModel.items.isEmpty ? "重新加载" : "清除筛选",
                            action: {
                                if viewModel.items.isEmpty {
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
                            providerSection(section.label, items: section.items)
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
        .navigationDestination(item: $selected) { item in
            CheckinItemDetailView(item: item)
        }
    }

    // MARK: - Overview

    private var overviewCard: some View {
        let c = viewModel.summary?.counts
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日总览")
                        .font(.headline)
                    if let t = viewModel.lastUpdated {
                        Text("更新于 \(t.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let gen = viewModel.summary?.generatedAt, !gen.isEmpty {
                        Text("服务端 \(gen)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                StatusPill(
                    title: "\(c?.healthyValue ?? 0)/\(c?.totalValue ?? 0) 正常",
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

            if let providers = viewModel.summary?.providers, !providers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(providers) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.displayLabel)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(p.countValue) 项 · 失败 \(p.counts?.failedValue ?? 0)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
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
                        tint: Color(hex: kind.colorHex)
                    ) {
                        viewModel.filterStatus = viewModel.filterStatus == kind ? nil : kind
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private func providerSection(_ title: String, items: [CheckinItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: title, systemImage: "checklist")
            VStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        selected = item
                    } label: {
                        CheckinItemRow(item: item)
                            .appCard()
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98))
                }
            }
        }
    }
}

// MARK: - Row

private struct CheckinItemRow: View {
    let item: CheckinItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.statusKind.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(hex: item.statusKind.colorHex))
                .frame(width: 36, height: 36)
                .background(
                    Color(hex: item.statusKind.colorHex).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
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
                title: item.statusKind.title,
                color: Color(hex: item.statusKind.colorHex),
                systemImage: item.statusKind.systemImage
            )
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName)，\(item.statusKind.title)，\(item.message ?? "")")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let msg = item.message, !msg.isEmpty {
            parts.append(msg)
        }
        if let d = item.pointsDelta {
            parts.append(d == floor(d) ? "+\(Int(d))" : String(format: "+%.1f", d))
            if let c = item.currency, !c.isEmpty { parts[parts.count - 1] += " \(c)" }
        }
        if let at = item.checkedAt, !at.isEmpty {
            parts.append(Self.shortTime(at))
        }
        return parts.isEmpty ? item.displayProvider : parts.joined(separator: " · ")
    }

    private static func shortTime(_ iso: String) -> String {
        // Keep ISO-ish readable without full parser dependency.
        if iso.count >= 16 {
            // 2026-07-21T02:12:03Z → 07-21 02:12
            let day = iso.dropFirst(5).prefix(5)
            let hm = iso.dropFirst(11).prefix(5)
            return "\(day) \(hm)"
        }
        return iso
    }
}

// MARK: - Detail

struct CheckinItemDetailView: View {
    let item: CheckinItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: item.statusKind.systemImage)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Color(hex: item.statusKind.colorHex))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayName)
                            .font(.title3.weight(.bold))
                        Text(item.displayProvider)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        title: item.statusKind.title,
                        color: Color(hex: item.statusKind.colorHex),
                        systemImage: item.statusKind.systemImage,
                        style: item.statusKind == .failed ? .solid : .soft
                    )
                }
                .appCardV2()

                detailCard

                if let msg = item.message, !msg.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        AppSectionTitle(title: "签到消息", systemImage: "text.bubble")
                        Text(msg)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard()
                    }
                }
            }
            .padding(16)
        }
        .background(AppSurfaceBackground(accent: Color(hex: item.statusKind.colorHex)))
        .navigationTitle("签到详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            row("状态", item.statusKind.title)
            Divider().opacity(0.4)
            row("签到源", item.displayProvider)
            if let bot = item.botUsername, !bot.isEmpty {
                Divider().opacity(0.4)
                row("Bot", "@\(bot)")
            }
            if let at = item.checkedAt, !at.isEmpty {
                Divider().opacity(0.4)
                row("时间", at)
            }
            if let d = item.pointsDelta {
                Divider().opacity(0.4)
                let unit = item.currency.map { " \($0)" } ?? ""
                let num = d == floor(d) ? "+\(Int(d))" : String(format: "+%.2f", d)
                row("变动", num + unit)
            }
            if let b = item.balance {
                Divider().opacity(0.4)
                let unit = item.currency.map { " \($0)" } ?? ""
                let num = b == floor(b) ? "\(Int(b))" : String(format: "%.2f", b)
                row("余额", num + unit)
            }
            if let s = item.streak {
                Divider().opacity(0.4)
                row("连续", s == floor(s) ? "\(Int(s)) 天" : String(format: "%.0f 天", s))
            }
            if let left = item.leftDays, !left.isEmpty {
                Divider().opacity(0.4)
                row("剩余天数", left)
            }
            if let notes = item.notes, !notes.isEmpty {
                Divider().opacity(0.4)
                row("备注", notes)
            }
            Divider().opacity(0.4)
            row("ID", item.id)
        }
        .appCardV2(padding: 4)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.medium))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
