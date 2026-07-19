import SwiftUI
import UIKit

/// 出口 IP 质量检测 · 对齐 MaYIHEI/paperclip ipquality 展示口径。
struct IPCheckHomeView: View {
    @StateObject private var viewModel = IPCheckViewModel()
    @State private var toast: String?
    @State private var includeMedia = true
    @State private var maskIP = false

    private let accent = IPCheckAccent.color

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                optionsBar

                if viewModel.isLoading && viewModel.result == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("多源检测中…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("出口探针 · 风险库 · 流媒体")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else if let result = viewModel.result, let info = result.primary {
                    statusCard(result)
                    ipCard(info, result: result)
                    basicCard(info, result: result)
                    if !result.typeRows.isEmpty {
                        typeCard(result.typeRows)
                    }
                    if !result.riskRows.isEmpty {
                        riskScoresCard(result.riskRows)
                    }
                    if !result.factorRows.isEmpty {
                        factorsCard(result.factorRows)
                    }
                    if includeMedia, !result.mediaRows.isEmpty {
                        mediaCard(result.mediaRows)
                    }
                    riskSummaryCard(result)
                    if !result.qualityNote.isEmpty {
                        Text(result.qualityNote)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ContentUnavailableView {
                        Label("无法获取 IP", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(viewModel.errorMessage ?? "请检查网络后重试")
                    } actions: {
                        Button("重新检测") {
                            Task { await viewModel.refresh(includeMedia: includeMedia) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                    .padding(.top, 24)
                }
            }
            .padding(16)
        }
        .background(AppSurfaceBackground(accent: accent))
        .navigationTitle("IP 检测")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .ipCheck, title: "IP 检测")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(includeMedia: includeMedia) }
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
            await viewModel.refresh(includeMedia: includeMedia)
        }
        .task {
            if viewModel.result == nil {
                await viewModel.refresh(includeMedia: includeMedia)
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

    // MARK: - Options

    private var optionsBar: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $includeMedia) {
                Text("流媒体/AI")
                    .font(.caption.weight(.semibold))
            }
            .toggleStyle(.button)
            .tint(accent)

            Toggle(isOn: $maskIP) {
                Text("隐藏 IP")
                    .font(.caption.weight(.semibold))
            }
            .toggleStyle(.button)
            .tint(accent)

            Spacer()
        }
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
                if result.probeTotal > 0 {
                    Text("出口探针 \(result.probeMatched)/\(result.probeTotal) 一致")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.isNative)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(result.isNative.contains("原生") ? Color.green : Color.orange)
                Text(result.isHomeBroadband)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .appCard()
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
                    Text(displayIP(info.query))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
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
            }

            if !info.nature.isEmpty {
                Text(info.nature)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(info.nature.contains("原生") ? Color.green : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (info.nature.contains("原生") ? Color.green : Color.orange).opacity(0.14),
                        in: Capsule()
                    )
            }

            if let cmp = result.compareIP, !cmp.isEmpty {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("对比源\(result.compareSource.map { "（\($0)）" } ?? "")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(displayIP(cmp))
                            .font(.body.monospaced())
                    }
                    Spacer()
                    Text(cmp != info.query ? "不一致" : "一致")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(cmp != info.query ? Color.orange : Color.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (cmp != info.query ? Color.orange : Color.green).opacity(0.15),
                            in: Capsule()
                        )
                }
            }
        }
        .appCard()
    }

    private func basicCard(_ info: IPGeoInfo, result: IPCheckResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("基础信息")
            row("ASN", info.asInfo.isEmpty ? "—" : info.asInfo)
            row("组织", info.org.isEmpty ? (info.isp.isEmpty ? "—" : info.isp) : info.org)
            if !info.route.isEmpty { row("路由", info.route) }
            if !info.registeredRegion.isEmpty { row("注册地", info.registeredRegion) }
            if !info.timezone.isEmpty { row("时区", info.timezone) }
            row("数据源", info.sourceLabel)
            if !result.pathStatus.isEmpty { row("本机路径", result.pathStatus) }
            row("判定依据", result.vpnMethod)
        }
        .appCard()
    }

    private func typeCard(_ rows: [IPTypeRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("IP 类型属性")
            ForEach(rows) { r in
                HStack {
                    Text(r.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if !r.usage.isEmpty {
                            Text("网络 \(r.usage)")
                                .font(.subheadline.weight(.medium))
                        }
                        if !r.company.isEmpty {
                            Text("公司 \(r.company)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                if r.id != rows.last?.id { Divider().opacity(0.4) }
            }
        }
        .appCard()
    }

    private func riskScoresCard(_ rows: [IPRiskRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("风险评分")
            ForEach(rows) { r in
                HStack {
                    Text(r.name)
                        .font(.caption.weight(.semibold))
                        .frame(width: 96, alignment: .leading)
                    Text(r.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(IPCheckAnalysis.riskColor(r.severity))
                    Spacer()
                    Text(r.detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if r.id != rows.last?.id { Divider().opacity(0.4) }
            }
        }
        .appCard()
    }

    private func factorsCard(_ rows: [IPFactorRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("风险因素")
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(r.name)
                            .font(.subheadline.weight(.semibold))
                        if !r.country.isEmpty {
                            Text(IPCheckAnalysis.flagEmoji(countryCode: r.country) + " " + r.country)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    FlowChecks(checks: r.checks)
                }
                if r.id != rows.last?.id { Divider().opacity(0.4) }
            }
        }
        .appCard()
    }

    private func mediaCard(_ rows: [IPMediaRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("流媒体与 AI")
            ForEach(rows) { r in
                HStack {
                    Text(r.name)
                        .font(.subheadline.weight(.medium))
                        .frame(width: 100, alignment: .leading)
                    Text(IPCheckAnalysis.mediaLabel(r.status))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(IPCheckAnalysis.mediaColor(r.status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(IPCheckAnalysis.mediaColor(r.status).opacity(0.14), in: Capsule())
                    if !r.region.isEmpty {
                        Text(r.region)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(r.note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if r.id != rows.last?.id { Divider().opacity(0.35) }
            }
        }
        .appCard()
    }

    private func riskSummaryCard(_ result: IPCheckResult) -> some View {
        let color: Color = result.riskValue > 60 ? .red : (result.riskValue > 20 ? .orange : .green)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本地启发式风险")
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
        .appCard()
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
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
        if v > 20 { return "存在部分代理或机房特征，请结合多源评分判断。" }
        return "更接近家宽/直连特征。"
    }

    private func displayIP(_ ip: String) -> String {
        guard maskIP, !ip.isEmpty else { return ip.isEmpty ? "—" : ip }
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).*.*"
        }
        if ip.count > 8 {
            return String(ip.prefix(4)) + "…****"
        }
        return "***"
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

// Simple wrap of factor chips
private struct FlowChecks: View {
    let checks: [(String, String)]

    var body: some View {
        FlexibleChips(items: checks.map { "\($0.0) \($0.1)" })
    }
}

private struct FlexibleChips: View {
    let items: [String]

    var body: some View {
        // Simple horizontal wrap via LazyVGrid
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items, id: \.self) { text in
                let bad = text.hasSuffix(" 是")
                Text(text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(bad ? Color.orange : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        (bad ? Color.orange : Color.secondary).opacity(0.12),
                        in: Capsule()
                    )
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

    func refresh(includeMedia: Bool = true) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let (res, err) = await service.check(includeMedia: includeMedia)
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
