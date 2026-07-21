import SwiftUI

enum DownloadFileSort: String, CaseIterable, Identifiable {
    case name
    case sizeDesc
    case kind

    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "名称"
        case .sizeDesc: return "大小"
        case .kind: return "类型"
        }
    }
}

/// Completed downloads with sort, grouping, and multi-select batch delete.
struct FilesListView: View {
    let files: [YTFileItem]
    var downloadingPath: String?
    var onShare: (YTFileItem) -> Void
    var onPlay: ((YTFileItem) -> Void)? = nil
    var onDelete: (YTFileItem) -> Void
    var onBatchDelete: (([YTFileItem]) -> Void)? = nil

    @State private var sort: DownloadFileSort = .name
    @State private var groupByKind = true
    @State private var selecting = false
    @State private var selected: Set<String> = []

    private var sortedFiles: [YTFileItem] {
        switch sort {
        case .name:
            return files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .sizeDesc:
            return files.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .kind:
            return files.sorted {
                let ka = DownloadMediaKind.detect(pathOrName: $0.name).title
                let kb = DownloadMediaKind.detect(pathOrName: $1.name).title
                if ka != kb { return ka < kb }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var grouped: [(String, [YTFileItem])] {
        guard groupByKind else { return [("全部", sortedFiles)] }
        var map: [String: [YTFileItem]] = [:]
        var order: [String] = []
        for f in sortedFiles {
            let key = DownloadMediaKind.detect(pathOrName: f.name).folderTitle
            if map[key] == nil {
                order.append(key)
                map[key] = []
            }
            map[key]?.append(f)
        }
        return order.compactMap { k in guard let v = map[k], !v.isEmpty else { return nil }; return (k, v) }
    }

    var body: some View {
        if files.isEmpty {
            Text("暂无已下载文件")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("排序", selection: $sort) {
                        ForEach(DownloadFileSort.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Toggle("按类型分组", isOn: $groupByKind)
                        .font(.caption)
                    Spacer()
                    Button(selecting ? "完成" : "多选") {
                        selecting.toggle()
                        if !selecting { selected.removeAll() }
                    }
                    .font(.caption.weight(.semibold))
                    if selecting, !selected.isEmpty {
                        Button("删除 \(selected.count)", role: .destructive) {
                            let items = files.filter { selected.contains($0.id) }
                            if let onBatchDelete {
                                onBatchDelete(items)
                            } else {
                                items.forEach(onDelete)
                            }
                            selected.removeAll()
                            selecting = false
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .font(.caption)

                ForEach(grouped, id: \.0) { group, items in
                    if groupByKind {
                        Text(group)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    ForEach(items) { file in
                        HStack(spacing: 8) {
                            if selecting {
                                Image(systemName: selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(file.id) ? Color.accentColor : .secondary)
                                    .onTapGesture {
                                        if selected.contains(file.id) {
                                            selected.remove(file.id)
                                        } else {
                                            selected.insert(file.id)
                                        }
                                    }
                            }
                            FileRowView(
                                file: file,
                                isDownloading: downloadingPath == file.path,
                                onShare: { onShare(file) },
                                onPlay: onPlay.map { handler in { handler(file) } },
                                onDelete: { onDelete(file) }
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard selecting else { return }
                            if selected.contains(file.id) {
                                selected.remove(file.id)
                            } else {
                                selected.insert(file.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension DownloadMediaKind {
    var title: String {
        switch self {
        case .video: return "video"
        case .image: return "image"
        case .other: return "other"
        }
    }

    var folderTitle: String {
        switch self {
        case .video: return "视频"
        case .image: return "图片"
        case .other: return "其它"
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
