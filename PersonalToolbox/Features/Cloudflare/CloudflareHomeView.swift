import SwiftUI

/// Cloudflare 监控面板 MVP（参考 CFPanel）：用量 + 域名列表。
struct CloudflareHomeView: View {
    /// When true (MonitorShellView), hide principal title — shell menu owns it.
    var hidesChromeTitle: Bool = false

    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = CloudflareViewModel()
    @State private var search = ""
    @State private var selectedZone: CFZone?

    private let accent = CloudflareAccent.color

    var body: some View {
        Group {
            if !settings.isCloudflareConfigured {
                ContentUnavailableView {
                    Label("未配置 Cloudflare", systemImage: "cloud")
                } description: {
                    Text("在设置中填写 API Token（推荐）与 Account ID，即可查看用量与域名。")
                } actions: {
                    Text("也可在本页设置入口填写。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    if let usage = viewModel.usage {
                        Section {
                            usageHeader(usage)
                        } header: {
                            Text("今日用量")
                        } footer: {
                            Text(usage.planName + " · 限额 \(usage.dailyLimit.formatted()) 请求/日（估算）")
                        }
                    }

                    Section {
                        if viewModel.isLoading && viewModel.zones.isEmpty {
                            HStack {
                                ProgressView()
                                Text("加载中…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if filteredZones.isEmpty {
                            Text(search.isEmpty ? "暂无域名" : "无匹配域名")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredZones) { zone in
                                Button {
                                    selectedZone = zone
                                } label: {
                                    zoneRow(zone)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("域名（\(filteredZones.count)）")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .searchable(text: $search, prompt: "搜索域名")
            }
        }
        .background(AppleTheme.canvas)
        .navigationTitle(hidesChromeTitle ? "" : "Cloudflare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !hidesChromeTitle {
                ToolbarItem(placement: .principal) {
                    ServiceBrandTitle(brand: .cloudflare, title: "Cloudflare")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(settings: settings) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading || !settings.isCloudflareConfigured)
                .accessibilityLabel("刷新")
            }
        }
        .refreshable {
            await viewModel.refresh(settings: settings)
        }
        .task {
            await viewModel.refresh(settings: settings)
        }
        .overlay(alignment: .bottom) {
            if let err = viewModel.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.9), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .navigationDestination(item: $selectedZone) { zone in
            CloudflareZoneDetailView(zone: zone)
        }
    }

    private var filteredZones: [CFZone] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return viewModel.zones }
        return viewModel.zones.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func usageHeader(_ usage: CFUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                metric("总计", value: usage.totalRequests, fraction: usage.totalFraction)
                metric("Workers", value: usage.workersRequests, fraction: usage.workersFraction)
                metric("Pages", value: usage.pagesRequests, fraction: usage.pagesFraction)
            }
            ProgressView(value: usage.totalFraction)
                .tint(accent)
        }
        .padding(.vertical, 6)
    }

    private func metric(_ title: String, value: Int, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.headline.monospacedDigit())
            Text(String(format: "%.1f%%", fraction * 100))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func zoneRow(_ zone: CFZone) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(zone.statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(zone.status)
                        .font(.caption)
                        .foregroundStyle(zone.statusColor)
                    if let plan = zone.planName {
                        Text(plan)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if zone.paused {
                        Text("已暂停")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - ViewModel

@MainActor
final class CloudflareViewModel: ObservableObject {
    @Published var zones: [CFZone] = []
    @Published var usage: CFUsageSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = CloudflareService.shared

    func refresh(settings: AppSettings) async {
        guard settings.isCloudflareConfigured else {
            zones = []
            usage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let cred = CFCredentials(settings: settings)
        async let zonesTask = service.listZones(cred: cred)
        async let usageTask: CFUsageSnapshot? = {
            do {
                return try await service.fetchUsage(cred: cred)
            } catch {
                // Account ID missing or GraphQL scope — still show zones
                return nil
            }
        }()

        do {
            zones = try await zonesTask
            usage = await usageTask
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
