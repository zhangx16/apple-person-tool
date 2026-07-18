import SwiftUI
import UIKit

/// 出口 IP / 代理启发式检测（参考 riccilnl IP检测.scripting）。
struct IPCheckHomeView: View {
    @StateObject private var viewModel = IPCheckViewModel()
    @State private var toast: String?

    private let accent = IPCheckAccent.color

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isLoading && viewModel.result == nil {
                    ProgressView("检测中…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let result = viewModel.result, let info = result.primary {
                    statusCard(result)
                    ipCard(info, result: result)
                    detailCard(info, result: result)
                    riskCard(result)
                    Text("结果为启发式判断，仅供自查代理/出口是否生效，非安全审计结论。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView {
                        Label("无法获取 IP", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(viewModel.errorMessage ?? "请检查网络后重试")
                    } actions: {
                        Button("重新检测") {
                            Task { await viewModel.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                    .padding(.top, 24)
                }
            }
            .padding(16)
        }
        .background(AppleTheme.canvas)
        .navigationTitle("IP 检测")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .ipCheck, title: "IP 检测")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("刷新")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            if viewModel.result == nil {
                await viewModel.refresh()
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.92), in: Capsule())
                    .padding(.top, 8)
            }
        }
        .animation(AppleTheme.preferredSnappy, value: toast)
    }

    // MARK: - Cards

    private func statusCard(_ result: IPCheckResult) -> some View {
        let vpnOn = result.vpnStatus == "已连接"
            || result.vpnStatus == "分流代理"
            || result.vpnStatus == "代理"
        return HStack(spacing: 12) {
            Image(systemName: vpnOn ? "lock.shield.fill" : "globe")
                .font(.title2)
                .foregroundStyle(vpnOn ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(vpnOn ? result.vpnStatus : "VPN \(result.vpnStatus)")
                    .font(.headline)
                Text(result.vpnMethod)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.isNative)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(result.isNative == "原生" ? Color.green : Color.orange)
                Text(result.isHomeBroadband)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private func ipCard(_ info: IPGeoInfo, result: IPCheckResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("出口 IP")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                copy(info.query)
            } label: {
                HStack {
                    Text(info.query.isEmpty ? "—" : info.query)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(accent)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Text(IPCheckAnalysis.flagEmoji(countryCode: info.countryCode))
                Text(locationLine(info))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if let cmp = result.compareIP, !cmp.isEmpty {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("对比源 IP\(result.compareSource.map { "（\($0)）" } ?? "")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(cmp)
                            .font(.body.monospaced())
                    }
                    Spacer()
                    if cmp != info.query {
                        Text("不一致")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    } else {
                        Text("一致")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }
                .onTapGesture { copy(cmp) }
            }
        }
        .padding(16)
        .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private func detailCard(_ info: IPGeoInfo, result: IPCheckResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("ISP", info.isp.isEmpty ? "—" : info.isp)
            row("组织", info.org.isEmpty ? "—" : info.org)
            if !info.asInfo.isEmpty {
                row("AS", info.asInfo)
            }
            row("数据源", info.sourceLabel)
            if !result.pathStatus.isEmpty {
                row("本机路径", result.pathStatus)
            }
            row("判定依据", result.vpnMethod)
            row("置信度", "\(result.vpnConfidence)%")
        }
        .padding(16)
        .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private func riskCard(_ result: IPCheckResult) -> some View {
        let color: Color = result.riskValue > 60 ? .red : (result.riskValue > 20 ? .orange : .green)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("风险评分")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(result.riskValue)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                Text("/ 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(result.riskValue), total: 100)
                .tint(color)
            Text(riskHint(result.riskValue))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func locationLine(_ info: IPGeoInfo) -> String {
        [info.country, info.regionName, info.city]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func riskHint(_ v: Int) -> String {
        if v > 60 { return "出口更像机房/代理，若你在用代理属正常。" }
        if v > 20 { return "存在部分代理或机房特征，请结合双源 IP 判断。" }
        return "更接近家宽/直连特征。"
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        withAnimation { toast = "已复制 \(text)" }
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                if toast?.contains(text) == true { toast = nil }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class IPCheckViewModel: ObservableObject {
    @Published var result: IPCheckResult?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = IPCheckService.shared

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let (res, err) = await service.check()
        if let res {
            result = res
            Haptics.success()
        } else {
            errorMessage = err
            if result == nil {
                Haptics.error()
            }
        }
    }
}
