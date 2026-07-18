import SwiftUI

/// Single download-queue row: title, status chip, progress, kill/clear actions.
struct TaskRowView: View {
    let task: YTTask
    var isSharing: Bool = false
    var onKill: () -> Void
    var onClear: () -> Void
    var onShare: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "film")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title.isEmpty ? task.url : task.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        statusChip
                        if !task.progressPercentText.isEmpty, task.isActive {
                            Text(task.progressPercentText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if !task.speed.isEmpty, task.isActive {
                            Text(task.speed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if task.isFailed, let err = task.error, !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                actions
            }

            if task.isActive || task.isCompleted {
                ProgressView(value: task.progress01)
                    .tint(task.isFailed ? .red : (task.isCompleted ? .green : Color.accentColor))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var statusChip: some View {
        Text(task.statusLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(chipForeground)
            .background(chipBackground, in: Capsule())
    }

    private var chipForeground: Color {
        switch task.processStatus {
        case 2: return .green
        case 3: return .red
        case 1: return .orange
        default: return .secondary
        }
    }

    private var chipBackground: Color {
        switch task.processStatus {
        case 2: return Color.green.opacity(0.15)
        case 3: return Color.red.opacity(0.15)
        case 1: return Color.orange.opacity(0.15)
        default: return Color(.tertiarySystemFill)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            if task.isCompleted, task.filepath != nil, let onShare {
                Button {
                    onShare()
                } label: {
                    if isSharing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("分享文件")
                .disabled(isSharing)
            }

            if task.isActive {
                Button(role: .destructive) {
                    onKill()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("取消下载")
            } else {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("清除任务")
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = [task.title, task.statusLabel]
        if task.isActive {
            parts.append(task.progressPercentText)
            if !task.speed.isEmpty { parts.append(task.speed) }
        }
        if task.isFailed, let e = task.error { parts.append(e) }
        return parts.filter { !$0.isEmpty }.joined(separator: "，")
    }
}

#Preview {
    List {
        TaskRowView(
            task: YTTask(
                id: "1",
                url: "https://example.com",
                title: "示例视频",
                status: "下载中",
                processStatus: 1,
                percentageRaw: "45.2%",
                progress: 0.452,
                speed: "1.2 MB/s",
                eta: "",
                filepath: nil,
                error: nil
            ),
            onKill: {},
            onClear: {}
        )
        TaskRowView(
            task: YTTask(
                id: "2",
                url: "https://example.com",
                title: "已完成视频",
                status: "已完成",
                processStatus: 2,
                percentageRaw: "-1",
                progress: 1,
                speed: "",
                eta: "",
                filepath: "/tmp/a.mp4",
                error: nil
            ),
            onKill: {},
            onClear: {},
            onShare: {}
        )
    }
}
