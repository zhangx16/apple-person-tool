import SwiftUI

struct KomariHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = KomariViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(settings.komariBaseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let err = viewModel.errorMessage {
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                if viewModel.rows.isEmpty && !viewModel.isLoading {
                    EmptyStateView(
                        symbol: "server.rack",
                        title: "暂无节点",
                        message: "确认 Komari 地址可访问，且公开接口 /api/nodes 已开启。"
                    )
                    .padding(.top, 24)
                }

                ForEach(viewModel.rows) { row in
                    nodeCard(row)
                }
            }
            .padding(16)
        }
        .background(AppleTheme.canvas)
        .navigationTitle("Komari")
        .overlay {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView("加载节点…")
            }
        }
        .refreshable { await viewModel.load(settings: settings) }
        .task { await viewModel.load(settings: settings) }
    }

    private func nodeCard(_ row: KomariNodeRow) -> some View {
        let n = row.node
        let r = row.recent
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(n.region ?? "")
                Text(n.name ?? n.uuid)
                    .font(.headline)
                Spacer()
                if let cpu = r?.cpu?.usage {
                    Text(String(format: "CPU %.0f%%", cpu))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(cpu > 80 ? .red : .secondary)
                }
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
                    Text("↑ \(formatBytes(net.up))  ↓ \(formatBytes(net.down))")
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

            if let tags = n.tags, !tags.isEmpty {
                Text(tags)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n.name ?? "节点") CPU \(Int(r?.cpu?.usage ?? 0)) 百分比")
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

    private func formatBytes(_ b: Int64?) -> String {
        guard let b else { return "-" }
        let d = Double(b)
        if d > 1_000_000 { return String(format: "%.1f MB/s", d / 1_000_000) }
        if d > 1_000 { return String(format: "%.1f KB/s", d / 1_000) }
        return "\(b) B/s"
    }

    private func formatUptime(_ seconds: Int64) -> String {
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        if d > 0 { return "运行 \(d)天\(h)时" }
        return "运行 \(h)时"
    }
}
