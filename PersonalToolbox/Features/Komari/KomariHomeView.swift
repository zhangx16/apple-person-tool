import SwiftUI

/// Komari public monitor console — APIs from [komari-monitor/komari](https://github.com/komari-monitor/komari).
struct KomariHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = KomariViewModel()
    @State private var selected: KomariNodeRow?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            searchBar
            content
        }
        .background(AppSurfaceBackground(accent: Color.accentColor))
        .navigationTitle(viewModel.siteName ?? "Komari")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .komari, title: viewModel.siteName ?? "Komari")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $viewModel.autoRefresh) {
                    Image(systemName: viewModel.autoRefresh ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
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

    private var headerBar: some View {
        HStack(spacing: 12) {
            metricChip("在线", "\(viewModel.onlineCount)/\(viewModel.rows.count)", .green)
            if let v = viewModel.versionText {
                metricChip("版本", v, .secondary)
            }
            Spacer()
            if let t = viewModel.lastUpdated {
                Text(t.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func metricChip(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索节点 / 地区 / 标签", text: $viewModel.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let err = viewModel.errorMessage {
            Text(err)
                .font(.subheadline)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
        }

        if viewModel.isLoading && viewModel.rows.isEmpty {
            ProgressView("加载节点…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredRows.isEmpty {
            EmptyStateView(
                symbol: "server.rack",
                title: viewModel.rows.isEmpty ? "暂无节点" : "无匹配节点",
                message: viewModel.rows.isEmpty
                    ? "确认 Komari 地址可访问，且公开接口 /api/nodes 已开启。"
                    : "试试其他关键词。"
            )
            .padding(.top, 24)
            Spacer()
        } else {
            List {
                ForEach(viewModel.filteredRows) { row in
                    Button {
                        selected = row
                    } label: {
                        nodeCard(row)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func nodeCard(_ row: KomariNodeRow) -> some View {
        let n = row.node
        let r = row.recent
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(row.isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(n.region ?? "")
                Text(n.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "CPU %.0f%%", row.cpuUsage))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(row.cpuUsage > 80 ? Color.red : Color.secondary)
            }

            if let os = n.os {
                Text(os)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let ram = r?.ram {
                labeledBar("内存", percent: ram.usedPercent)
            }
            if let disk = r?.disk {
                labeledBar("磁盘", percent: disk.usedPercent)
            }

            HStack {
                if let net = r?.network {
                    Text("↑ \(formatRate(net.up))  ↓ \(formatRate(net.down))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let up = r?.uptime {
                    Text(formatUptime(up))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let totalUp = r?.network?.totalUp, let totalDown = r?.network?.totalDown {
                Text("累计 ↑ \(formatBytes(totalUp))  ↓ \(formatBytes(totalDown))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 6) {
                if let tags = n.tags, !tags.isEmpty {
                    Text(tags)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                if let limit = n.trafficLimit, limit > 0 {
                    Text("流量上限 \(formatBytes(limit))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n.displayName) \(row.isOnline ? "在线" : "离线") CPU \(Int(row.cpuUsage)) 百分比")
    }

    private func labeledBar(_ title: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: min(max(percent, 0), 100), total: 100)
                .tint(percent > 90 ? .red : .accentColor)
        }
    }
}

// MARK: - Detail

private struct KomariNodeDetailView: View {
    let row: KomariNodeRow
    @ObservedObject var viewModel: KomariViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                if let err = viewModel.detailError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
                hoursPicker
                historySection
                pingSection
                infoSection
            }
            .padding(16)
        }
        .background(AppSurfaceBackground(accent: Color.accentColor))
        .navigationTitle(row.node.displayName)
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

    private var summaryCard: some View {
        let r = row.recent
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(row.isOnline ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(row.isOnline ? "在线" : "离线 / 无近期数据")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(row.node.region ?? "")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                kv("CPU", String(format: "%.1f%%", r?.cpu?.usage ?? 0))
                kv("内存", String(format: "%.0f%%", r?.ram?.usedPercent ?? 0))
                kv("磁盘", String(format: "%.0f%%", r?.disk?.usedPercent ?? 0))
                kv("进程", "\(r?.process ?? 0)")
                kv("TCP", "\(r?.connections?.tcp ?? 0)")
                kv("UDP", "\(r?.connections?.udp ?? 0)")
            }
            if let load = r?.load {
                Text(String(format: "Load %.2f / %.2f / %.2f", load.load1 ?? 0, load.load5 ?? 0, load.load15 ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let net = r?.network {
                Text("实时 ↑ \(formatRate(net.up))  ↓ \(formatRate(net.down))")
                    .font(.caption.monospacedDigit())
                Text("累计 ↑ \(formatBytes(net.totalUp))  ↓ \(formatBytes(net.totalDown))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let up = r?.uptime {
                Text(formatUptime(up)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            if viewModel.isDetailLoading && viewModel.loadRecords.isEmpty {
                ProgressView("加载记录…")
            } else if viewModel.loadRecords.isEmpty {
                Text("暂无历史（或未开启 record）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                sparkline(values: viewModel.loadRecords.compactMap(\.cpu), maxHint: 100)
                ForEach(viewModel.loadRecords.suffix(8).reversed()) { rec in
                    HStack {
                        Text(shortTime(rec.time))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        ProgressView(value: min(rec.cpu ?? 0, 100), total: 100)
                        Text(String(format: "%.0f%%", rec.cpu ?? 0))
                            .font(.caption2.monospacedDigit())
                            .frame(width: 36, alignment: .trailing)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
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
                        Spacer()
                        Text(String(format: "min %.0f · max %.0f ms", b.min ?? 0, b.max ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private var infoSection: some View {
        let n = row.node
        return VStack(alignment: .leading, spacing: 8) {
            Text("机器信息").font(.headline)
            infoRow("UUID", n.uuid)
            infoRow("CPU", n.cpuName ?? "—")
            infoRow("核心", n.cpuCores.map(String.init) ?? "—")
            infoRow("架构", n.arch ?? "—")
            infoRow("系统", n.os ?? "—")
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(v).font(.caption).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func sparkline(values: [Double], maxHint: Double) -> some View {
        let maxV = max(maxHint, values.max() ?? 1, 1)
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                guard values.count > 1 else { return }
                for (i, v) in values.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(values.count - 1)
                    let y = h * (1 - CGFloat(min(v, maxV) / maxV))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .frame(height: 48)
        .padding(.vertical, 4)
    }

    private func shortTime(_ raw: String?) -> String {
        guard let raw, raw.count >= 16 else { return raw ?? "—" }
        // 2026-07-18T12:41:52Z -> 12:41
        let t = raw.dropFirst(11).prefix(5)
        return String(t)
    }
}

// MARK: - Shared formatters

private func formatRate(_ b: Int64?) -> String {
    guard let b else { return "-" }
    let d = Double(b)
    if d > 1_000_000 { return String(format: "%.1f MB/s", d / 1_000_000) }
    if d > 1_000 { return String(format: "%.1f KB/s", d / 1_000) }
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
    if d > 0 { return "运行 \(d)天\(h)时" }
    if h > 0 { return "运行 \(h)时\(m)分" }
    return "运行 \(m)分"
}
