import SwiftUI

/// Completed downloads on the server filebrowser.
struct FilesListView: View {
    let files: [YTFileItem]
    var downloadingPath: String?
    var onShare: (YTFileItem) -> Void
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
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)

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

            Spacer(minLength: 0)

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
            .disabled(isDownloading)
            .accessibilityLabel("分享下载")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除文件")
        }
        .padding(.vertical, 4)
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
