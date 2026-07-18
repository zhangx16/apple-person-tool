import SwiftUI

/// Completed downloads on the server filebrowser.
struct FilesListView: View {
    let files: [YTFileItem]
    var downloadingPath: String?
    var onShare: (YTFileItem) -> Void
    var onPlay: ((YTFileItem) -> Void)? = nil
    var onDelete: (YTFileItem) -> Void

    var body: some View {
        if files.isEmpty {
            Text("暂无已下载文件")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            ForEach(files) { file in
                FileRowView(
                    file: file,
                    isDownloading: downloadingPath == file.path,
                    onShare: { onShare(file) },
                    onPlay: onPlay.map { handler in { handler(file) } },
                    onDelete: { onDelete(file) }
                )
            }
        }
    }
}

struct FileRowView: View {
    let file: YTFileItem
    var isDownloading: Bool = false
    var onShare: () -> Void
    var onPlay: (() -> Void)? = nil
    var onDelete: () -> Void

    private var canPlay: Bool {
        DownloadMediaKind.detect(pathOrName: file.name).isPlayableVideo
            || DownloadMediaKind.detect(pathOrName: file.path).isPlayableVideo
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if canPlay { onPlay?() }
            } label: {
                Image(systemName: canPlay ? "play.circle.fill" : "doc.fill")
                    .font(.title3)
                    .foregroundStyle(canPlay ? Color.accentColor : Color.secondary)
                    .frame(width: 32)
            }
            .buttonStyle(.borderless)
            .disabled(!canPlay || isDownloading)
            .accessibilityLabel(canPlay ? "播放 \(file.name)" : file.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if !file.sizeText.isEmpty {
                    Text(file.sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(file.sizeText.isEmpty ? file.name : "\(file.name)，\(file.sizeText)")

            Spacer(minLength: 0)

            if canPlay, let onPlay {
                Button {
                    onPlay()
                } label: {
                    if isDownloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(isDownloading)
                .accessibilityLabel("播放 \(file.name)")
            }

            Button {
                onShare()
            } label: {
                if isDownloading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(isDownloading)
            .accessibilityLabel("分享 \(file.name)")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("删除 \(file.name)")
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }
}

#Preview {
    List {
        FilesListView(
            files: [
                YTFileItem(id: "1", name: "demo.mp4", size: 120_000_000, path: "/downloads/demo.mp4")
            ],
            onShare: { _ in },
            onDelete: { _ in }
        )
    }
}
