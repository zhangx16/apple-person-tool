import SwiftUI
import UIKit

/// IP 风险聚合查询 · 参考 IPSuper 一站式体验 + ipquality 多库口径。
struct IPCheckHomeView: View {
    @StateObject private var viewModel = IPCheckViewModel()
    @State private var toast: String?
    @State private var includeMedia = true
    @State private var maskIP = false
    @State private var queryIP = ""
    @FocusState private var queryFocused: Bool

    private let accent = IPCheckAccent.color

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                queryBar
                optionsBar

                if viewModel.isLoading && viewModel.result == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("多源聚合检测中…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("出口探针 · 风险库 · 网络画像 · 流媒体")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else if let result = viewModel.result, let info = result.primary {
                    riskCoefficientHero(result)
                    if !result.portraitTags.isEmpty {
                        portraitCard(result.portraitTags)
                    }
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
                        Button("检测当前出口") {
                            queryIP = ""
                            Task { await viewModel.refresh(targetIP: nil, includeMedia: includeMedia) }
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
                    Task { await runCheck() }
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
            await runCheck()
        }
        .task {
            if viewModel.result == nil {
                await runCheck()
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

    // MARK: - Query (IPSuper-style)

    private var queryBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IP 风险信息聚合查询")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("留空=当前出口，或输入要查询的 IP", text: $queryIP)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .focused($queryFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await runCheck() } }
                Button {
                    Task { await runCheck() }
                } label: {
                    Text("查询")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(accent.brandGradient, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

            HStack(spacing: 8) {
                Button {
                    queryIP = ""
                    Task { await runCheck() }
                } label: {
                    Label("当前出口", systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .controlSize(.small)

                if let ip = viewModel.result?.primary?.query, !ip.isEmpty {
                    Button {
                        queryIP = ip
                    } label: {
                        Text("填入当前 IP")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
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
            .disabled(!queryIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Toggle(isOn: $maskIP) {
                Text("隐藏 IP")
                    .font(.caption.weight(.semibold))
            }
            .toggleStyle(.button)
            .tint(accent)

            Spacer()
        }
    }

    private func runCheck() async {
        queryFocused = false
        let raw = queryIP.trimmingCharacters(in: .whitespacesAndNewlines)
        await viewModel.refresh(
            targetIP: raw.isEmpty ? nil : raw,
            includeMedia: includeMedia && raw.isEmpty
        )
    }

    // MARK: - Cards

    /// IPSuper 风格风险系数大卡片 — 环形仪表盘 Hero
    private func riskCoefficientHero(_ result: IPCheckResult) -> some View {
        let v = result.riskValue
        let color: Color = v >= 66 ? .red : (v >= 33 ? .orange : accent)
        let label = v >= 66 ? "高风险" : (v >= 33 ? "中风险" : "低风险")
        return HStack(spacing: 20) {
            // 环形仪表盘
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(v) / 100)
                    .stroke(
                        color.brandGradient,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(AppleTheme.preferredGentle, value: v)
                VStack(spacing: 2) {
                    Text("\(v)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                    Text("/ 100")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 108, height: 108)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("风险系数 \(v)，满分 100，\(label)")

            VStack(alignment: .leading, spacing: 10) {
                Text(result.isLookupMode ? "查询 IP 风险系数" : "当前出口风险系数")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(color.brandGradient, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                    }
                    .shadow(color: color.opacity(0.3), radius: 6, y: 2)
                Text(riskHint(v))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .appCardV2()
    }

    private func portraitCard(_ tags: [IPPortraitTag]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("网络画像")
                .font(.subheadline.weight(.bold))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(tags) { tag in
                    Text(tag.text)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(portraitFg(tag.level))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(portraitBg(tag.level), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .appCard()
    }

    private func portraitFg(_ level: String) -> Color {
        switch level {
        case "high": return .white
        case "mid": return Color(hex: 0x92400E)
        case "low": return Color(hex: 0x065F46)
        default: return .primary
        }
    }

    private func portraitBg(_ level: String) -> Color {
        switch level {
        case "high": return .red.opacity(0.85)
        case "mid": return Color(hex: 0xFBBF24).opacity(0.35)
        case "low": return accent.opacity(0.22)
        default: return Color(.tertiarySystemFill)
        }
    }

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
    let checks: [IPFactorCheck]

    var body: some View {
        FlexibleChips(items: checks.map { "\($0.key) \($0.value)" })
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

    func refresh(targetIP: String? = nil, includeMedia: Bool = true) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let (res, err) = await service.check(targetIP: targetIP, includeMedia: includeMedia)
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
