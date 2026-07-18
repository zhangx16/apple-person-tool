import SwiftUI

/// Connectivity probe status shown under each service section.
enum ServiceProbeState: Equatable {
    case unknown
    case probing
    case success(latencyMs: Int, detail: String?)
    case failure(String)

    var isProbing: Bool {
        if case .probing = self { return true }
        return false
    }
}

/// Status row: ● 未知 / 检测中 / 成功(延迟 ms) / 失败(摘要).
struct ServiceProbeRow: View {
    let state: ServiceProbeState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(titleColor)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            if state.isProbing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var title: String {
        switch state {
        case .unknown: return "未检测"
        case .probing: return "检测中…"
        case .success: return "连接成功"
        case .failure: return "连接失败"
        }
    }

    private var subtitle: String? {
        switch state {
        case .unknown, .probing:
            return nil
        case .success(let ms, let detail):
            if let detail, !detail.isEmpty {
                return "\(ms) ms · \(detail)"
            }
            return "\(ms) ms"
        case .failure(let message):
            return message
        }
    }

    private var titleColor: Color {
        switch state {
        case .unknown, .probing: return .secondary
        case .success: return .primary
        case .failure: return .red
        }
    }

    private var dotColor: Color {
        switch state {
        case .unknown: return Color(.tertiaryLabel)
        case .probing: return .orange
        case .success: return .green
        case .failure: return .red
        }
    }

    private var accessibilityText: String {
        if let subtitle {
            return "\(title)，\(subtitle)"
        }
        return title
    }
}

#Preview {
    List {
        ServiceProbeRow(state: .unknown)
        ServiceProbeRow(state: .probing)
        ServiceProbeRow(state: .success(latencyMs: 128, detail: "3 个模型"))
        ServiceProbeRow(state: .failure("未授权，请检查密钥或重新登录"))
    }
}
