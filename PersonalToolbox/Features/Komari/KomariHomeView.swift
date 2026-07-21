import SwiftUI

/// Komari public monitor console — UI aligned with
/// [komari-monitor/komari-web](https://github.com/komari-monitor/komari-web) NodeCard / Dashboard.
struct KomariHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = KomariViewModel()
    @State private var selected: KomariNodeRow?

    private let brand = ServiceBrand.komari.tint

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dashboardBar
                searchBar
                contentList
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(AppSurfaceBackground(accent: brand))
        .navigationTitle(viewModel.siteName ?? "Komari")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .komari, title: viewModel.siteName ?? "Komari")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $viewModel.autoRefresh) {
                    Image(systemName: viewModel.autoRefresh
                          ? "arrow.triangle.2.circlepath.circle.fill"
                          : "arrow.triangle.2.circlepath.circle")
                }
                .toggleStyle(.button)
                .accessibilityLabel("自动刷新")
            }
        }
        .refreshable { await viewModel.load(settings: settings) }
        .task {
            await viewModel.load(settings: settings)
            viewModel.startAutoRefresh(settings: settings)
        }
        .onChange(of: viewModel.autoRefresh) { _, on in
            if on {
                viewModel.startAutoRefresh(settings: settings)
            } else {
                viewModel.stopAutoRefresh()
            }
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .navigationDestination(item: $selected) { row in
            KomariNodeDetailView(row: row, viewModel: viewModel)
        }
    }

    // MARK: - Dashboard overview (official Server.tsx style)

    private var dashboardBar: some View {
        VStack(spacing: 0) {
            dashRow("当前时间", Date().formatted(date: .abbreviated, time: .shortened))
            Divider().opacity(0.35)
            dashRow("在线节点", "\(viewModel.onlineCount) / \(viewModel.rows.count)")
            Divider().opacity(0.35)
            dashRow("地区", "\(viewModel.regionCount)")
            Divider().opacity(0.35)
            dashRow("流量总览", trafficOverviewText)
            if let v = viewModel.versionText {
                Divider().opacity(0.35)
                dashRow("版本", v)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppStroke.highlight, lineWidth: 1)
        }
        .modifier(AppShadow.mid())
    }

    private func dashRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }

    private var trafficOverviewText: String {
        let up = viewModel.rows.compactMap { $0.recent?.network?.totalUp }.reduce(0, +)
        let down = viewModel.rows.compactMap { $0.recent?.network?.totalDown }.reduce(0, +)
        return "↑ \(formatBytes(up))  /  ↓ \(formatBytes(down))"
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索节点 / 地区 / 标签 / OS", text: $viewModel.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !viewModel.search.isEmpty {
                Button {
                    viewModel.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        .overlay {
            Capsule().strokeBorder(AppStroke.highlight, lineWidth: 1)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var contentList: some View {
        if let err = viewModel.errorMessage {
            Text(err)
                .font(.subheadline)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        if viewModel.isLoading && viewModel.rows.isEmpty {
            ProgressView("加载节点…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if viewModel.sortedFilteredRows.isEmpty {
            EmptyStateView(
                symbol: "server.rack",
                title: viewModel.rows.isEmpty ? "暂无节点" : "无匹配节点",
                message: viewModel.rows.isEmpty
                    ? "确认 Komari 地址可访问，且公开接口 /api/nodes 已开启。"
                    : "试试其他关键词。",
                pathHint: "设置 → Komari"
            )
            .frame(minHeight: 260)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.sortedFilteredRows) { row in
                    Button {
                        selected = row
                    } label: {
                        KomariNodeCard(row: row)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98))
                }
            }
        }
    }
}

// MARK: - Node card (official NodeCard mobile layout)

private struct KomariNodeCard: View {
    let row: KomariNodeRow

    private var n: KomariNode { row.node }
    private var r: KomariRecentSample? { row.recent }

    private var ramPercent: Double {
        if let p = r?.ram?.usedPercent, p > 0 { return p }
        return 0
    }

    private var diskPercent: Double {
        if let p = r?.disk?.usedPercent, p > 0 { return p }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row: flag + name + online badge
            HStack(alignment: .center, spacing: 10) {
                Text(flagEmoji(for: n.region))
                    .font(.title2)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(n.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if row.isOnline, let up = r?.uptime {
                        Text(formatUptime(up))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if !row.isOnline {
                        Text(n.region ?? "离线")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(row.isOnline ? "在线" : "离线")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.isOnline ? Color(hex: 0x15803D) : Color(hex: 0xB91C1C))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (row.isOnline ? Color(hex: 0x30D158) : Color(hex: 0xFF453A)).opacity(0.14),
                        in: Capsule()
                    )
            }

            Divider().opacity(0.35)

            // Usage bars: CPU / RAM / Disk (official UsageBar)
            VStack(spacing: 8) {
                usageBar(label: "CPU", value: row.cpuUsage)
                usageBar(label: "内存", value: ramPercent, detail: memDetail)
                usageBar(label: "磁盘", value: diskPercent, detail: diskDetail)
            }

            // Network rows
            metricLine(title: "网速", value: networkSpeedText)
            metricLine(title: "总流量", value: totalTrafficText)

            HStack(spacing: 6) {
                if let tags = n.tags, !tags.isEmpty {
                    ForEach(tags.split(separator: ",").prefix(3).map(String.init), id: \.self) { tag in
                        Text(tag.trimmingCharacters(in: .whitespaces))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ServiceBrand.komari.tint.opacity(0.12), in: Capsule())
                    }
                }
                if let os = n.os {
                    Text("\(formatOs(os))\(n.arch.map { " · \($0)" } ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppStroke.highlight, lineWidth: 1)
        }
        .modifier(AppShadow.mid())
        .opacity(row.isOnline ? 1 : 0.78)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n.displayName)，\(row.isOnline ? "在线" : "离线")，CPU \(Int(row.cpuUsage))%")
    }

    private var memDetail: String? {
        guard let used = r?.ram?.used, let total = n.memTotal ?? r?.ram?.total, total > 0 else { return nil }
        return "\(formatBytes(used)) / \(formatBytes(total))"
    }

    private var diskDetail: String? {
        guard let used = r?.disk?.used, let total = n.diskTotal ?? r?.disk?.total, total > 0 else { return nil }
        return "\(formatBytes(used)) / \(formatBytes(total))"
    }

    private var networkSpeedText: String {
        let up = formatRate(r?.network?.up)
        let down = formatRate(r?.network?.down)
        return "↑ \(up)  ↓ \(down)"
    }

    private var totalTrafficText: String {
        let up = formatBytes(r?.network?.totalUp)
        let down = formatBytes(r?.network?.totalDown)
        return "↑ \(up)  ↓ \(down)"
    }

    private func usageBar(label: String, value: Double, detail: String? = nil) -> some View {
        let clamped = min(max(value, 0), 100)
        let tint: Color = clamped > 90 ? Color(hex: 0xFF453A) : (clamped > 70 ? Color(hex: 0xFF9F0A) : ServiceBrand.komari.tint)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", clamped))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(4, geo.size.width * CGFloat(clamped / 100)))
                }
            }
            .frame(height: 7)
            if let detail {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func metricLine(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Detail (official ServerDetail + NodeInfoPanel style)

private struct KomariNodeDetailView: View {
    let row: KomariNodeRow
    @ObservedObject var viewModel: KomariViewModel
    @EnvironmentObject private var settings: AppSettings

    private var live: KomariNodeRow {
        viewModel.rows.first(where: { $0.node.uuid == row.node.uuid }) ?? row
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                identityCard
                liveStatsGrid
                networkCard
                hoursPicker
                historySection
                pingSection
                infoSection
            }
            .padding(16)
        }
        .background(AppSurfaceBackground(accent: ServiceBrand.komari.tint))
        .navigationTitle(live.node.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetail(settings: settings, uuid: row.node.uuid)
        }
        .onChange(of: viewModel.detailHours) { _, _ in
            Task { await viewModel.loadDetail(settings: settings, uuid: row.node.uuid) }
        }
        .refreshable {
            await viewModel.loadDetail(settings: settings, uuid: row.node.uuid)
        }
    }

    private var identityCard: some View {
        HStack(spacing: 12) {
            Text(flagEmoji(for: live.node.region))
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 4) {
                Text(live.node.displayName)
                    .font(.title3.weight(.bold))
                HStack(spacing: 8) {
                    StatusPill(
                        title: live.isOnline ? "在线" : "离线",
                        color: live.isOnline ? Color(hex: 0x30D158) : Color(hex: 0xFF453A),
                        systemImage: live.isOnline ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    if let region = live.node.region, !region.isEmpty {
                        Text(region)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if live.isOnline, let up = live.recent?.uptime {
                    Text(formatUptime(up))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppStroke.highlight, lineWidth: 1)
        }
    }

    private var liveStatsGrid: some View {
        let r = live.recent
        let ramP = r?.ram?.usedPercent ?? 0
        let diskP = r?.disk?.usedPercent ?? 0
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile("CPU", String(format: "%.1f%%", r?.cpu?.usage ?? 0), r?.cpu?.usage ?? 0)
            statTile("内存", String(format: "%.0f%%", ramP), ramP)
            statTile("磁盘", String(format: "%.0f%%", diskP), diskP)
            statTile("进程", "\(r?.process ?? 0)", nil)
            statTile("TCP", "\(r?.connections?.tcp ?? 0)", nil)
            statTile("UDP", "\(r?.connections?.udp ?? 0)", nil)
        }
    }

    private func statTile(_ title: String, _ value: String, _ percent: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            if let percent {
                ProgressView(value: min(max(percent, 0), 100), total: 100)
                    .tint(percent > 90 ? Color(hex: 0xFF453A) : ServiceBrand.komari.tint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var networkCard: some View {
        let r = live.recent
        return VStack(alignment: .leading, spacing: 10) {
            Text("网络").font(.headline)
            if let load = r?.load {
                Text(String(format: "Load  %.2f / %.2f / %.2f", load.load1 ?? 0, load.load5 ?? 0, load.load15 ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let net = r?.network {
                HStack {
                    Label("实时", systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("↑ \(formatRate(net.up))  ↓ \(formatRate(net.down))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                HStack {
                    Label("累计", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("↑ \(formatBytes(net.totalUp))  ↓ \(formatBytes(net.totalDown))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var hoursPicker: some View {
        Picker("历史范围", selection: $viewModel.detailHours) {
            Text("1小时").tag(1)
            Text("6小时").tag(6)
            Text("24小时").tag(24)
        }
        .pickerStyle(.segmented)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("负载历史（CPU）").font(.headline)
            if let err = viewModel.detailError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
            if viewModel.isDetailLoading && viewModel.loadRecords.isEmpty {
                ProgressView("加载记录…")
            } else if viewModel.loadRecords.isEmpty {
                Text("暂无历史（或未开启 record）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                sparkline(values: viewModel.loadRecords.compactMap(\.cpu), maxHint: 100)
                ForEach(viewModel.loadRecords.suffix(10).reversed()) { rec in
                    HStack(spacing: 8) {
                        Text(shortTime(rec.time))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        ProgressView(value: min(rec.cpu ?? 0, 100), total: 100)
                            .tint(ServiceBrand.komari.tint)
                        Text(String(format: "%.0f%%", rec.cpu ?? 0))
                            .font(.caption2.monospacedDigit())
                            .frame(width: 34, alignment: .trailing)
                        Text(String(format: "RAM %.0f%%", rec.ramPercent))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ping 摘要").font(.headline)
            if viewModel.pingBasics.isEmpty {
                Text("暂无 Ping 统计")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.pingBasics) { b in
                    HStack {
                        Text("丢包 \(String(format: "%.1f%%", b.loss ?? 0))")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "min %.0f · max %.0f ms", b.min ?? 0, b.max ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var infoSection: some View {
        let n = live.node
        return VStack(alignment: .leading, spacing: 8) {
            Text("机器信息").font(.headline)
            infoRow("UUID", n.uuid)
            infoRow("CPU", n.cpuName ?? "—")
            infoRow("核心", n.cpuCores.map(String.init) ?? "—")
            infoRow("架构", n.arch ?? "—")
            infoRow("系统", n.os.map(formatOs) ?? "—")
            infoRow("内核", n.kernelVersion ?? "—")
            infoRow("虚拟化", n.virtualization ?? "—")
            infoRow("内存", formatBytes(n.memTotal))
            infoRow("磁盘", formatBytes(n.diskTotal))
            if let price = n.price {
                infoRow("价格", "\(n.currency ?? "")\(price)")
            }
            if let exp = n.expiredAt {
                infoRow("到期", exp)
            }
            if let limit = n.trafficLimit {
                infoRow("流量上限", formatBytes(limit))
            }
            if let tags = n.tags, !tags.isEmpty {
                infoRow("标签", tags)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(v)
                .font(.caption)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func sparkline(values: [Double], maxHint: Double) -> some View {
        let maxV = max(maxHint, values.max() ?? 1, 1)
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // fill under curve
                Path { path in
                    guard values.count > 1 else { return }
                    for (i, v) in values.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(values.count - 1)
                        let y = h * (1 - CGFloat(min(v, maxV) / maxV))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(ServiceBrand.komari.tint.opacity(0.12))

                Path { path in
                    guard values.count > 1 else { return }
                    for (i, v) in values.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(values.count - 1)
                        let y = h * (1 - CGFloat(min(v, maxV) / maxV))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(ServiceBrand.komari.tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
        .frame(height: 56)
        .padding(.vertical, 4)
    }

    private func shortTime(_ raw: String?) -> String {
        guard let raw, raw.count >= 16 else { return raw ?? "—" }
        return String(raw.dropFirst(11).prefix(5))
    }
}

// MARK: - ViewModel extras

extension KomariViewModel {
    /// Online first (official NodeGrid sort), then name.
    var sortedFilteredRows: [KomariNodeRow] {
        filteredRows.sorted { a, b in
            if a.isOnline != b.isOnline { return a.isOnline && !b.isOnline }
            let aw = a.node.weight ?? 0
            let bw = b.node.weight ?? 0
            if aw != bw { return aw > bw }
            return a.node.displayName.localizedCaseInsensitiveCompare(b.node.displayName) == .orderedAscending
        }
    }

    var regionCount: Int {
        Set(rows.compactMap { $0.node.region?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count
    }
}

// MARK: - Formatters (aligned with komari-web)

private func formatRate(_ b: Int64?) -> String {
    guard let b else { return "-" }
    let d = Double(b)
    if d >= 1_073_741_824 { return String(format: "%.2f GB/s", d / 1_073_741_824) }
    if d >= 1_048_576 { return String(format: "%.2f MB/s", d / 1_048_576) }
    if d >= 1024 { return String(format: "%.1f KB/s", d / 1024) }
    return "\(b) B/s"
}

private func formatBytes(_ b: Int64?) -> String {
    guard let b else { return "—" }
    let d = Double(b)
    if d >= 1_099_511_627_776 { return String(format: "%.2f TB", d / 1_099_511_627_776) }
    if d >= 1_073_741_824 { return String(format: "%.2f GB", d / 1_073_741_824) }
    if d >= 1_048_576 { return String(format: "%.1f MB", d / 1_048_576) }
    if d >= 1024 { return String(format: "%.0f KB", d / 1024) }
    return "\(b) B"
}

private func formatUptime(_ seconds: Int64) -> String {
    let d = seconds / 86400
    let h = (seconds % 86400) / 3600
    let m = (seconds % 3600) / 60
    if d > 0 { return "运行 \(d) 天 \(h) 时" }
    if h > 0 { return "运行 \(h) 时 \(m) 分" }
    return "运行 \(m) 分"
}

/// Short OS label like komari-web `formatOs`.
private func formatOs(_ os: String) -> String {
    let patterns: [(String, String)] = [
        ("debian", "Debian"), ("ubuntu", "Ubuntu"), ("windows", "Windows"),
        ("arch", "Arch"), ("alpine", "Alpine"), ("centos", "CentOS"),
        ("fedora", "Fedora"), ("red hat", "RHEL"), ("opensuse", "openSUSE"),
        ("manjaro", "Manjaro")
    ]
    let lower = os.lowercased()
    for (key, name) in patterns where lower.contains(key) {
        return name
    }
    return os.split(whereSeparator: { $0 == " " || $0 == "/" }).first.map(String.init) ?? os
}

/// Region → flag emoji (ISO country code or common aliases).
private func flagEmoji(for region: String?) -> String {
    guard var code = region?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
        return "🌐"
    }
    // Already emoji / long name
    if code.count > 3 { return "🌐" }
    // common aliases
    let aliases: [String: String] = [
        "CN": "CN", "HK": "HK", "TW": "TW", "MO": "MO",
        "JP": "JP", "KR": "KR", "SG": "SG", "US": "US",
        "UK": "GB", "GB": "GB", "DE": "DE", "FR": "FR",
        "NL": "NL", "RU": "RU", "IN": "IN", "AU": "AU"
    ]
    code = code.uppercased()
    if let mapped = aliases[code] { code = mapped }
    guard code.count == 2, code.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else {
        return "🌐"
    }
    let base: UInt32 = 127397
    var s = ""
    for u in code.unicodeScalars {
        if let scalar = UnicodeScalar(base + u.value) {
            s.unicodeScalars.append(scalar)
        }
    }
    return s.isEmpty ? "🌐" : s
}
