import SwiftUI
import UIKit

/// Download tab: URL + quality presets, running queue, completed files, Share export.
struct DownloadHomeView: View {
    /// From `RootTabView` selection — preferred over onAppear under TabView.
    var isTabSelected: Bool = true

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = DownloadViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let banner = viewModel.errorBanner {
                    Section {
                        bannerRow(text: banner, color: .red) {
                            viewModel.errorBanner = nil
                        }
                    }
                }
                if let info = viewModel.infoBanner {
                    Section {
                        bannerRow(text: info, color: .green) {
                            viewModel.infoBanner = nil
                        }
                    }
                }

                composeSection
                if let meta = viewModel.metadata {
                    metadataSection(meta)
                }
                tasksSection
                filesSection
            }
            .listStyle(.insetGrouped)
            .background(AppleTheme.canvas)
            .navigationTitle("下载")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshNow() }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("刷新")
                    .disabled(viewModel.isRefreshing)
                }
            }
            .refreshable {
                await viewModel.refreshNow()
            }
            .onAppear {
                viewModel.setTabVisible(isTabSelected)
                viewModel.onScenePhase(scenePhase)
            }
            .onChange(of: isTabSelected) { _, selected in
                viewModel.setTabVisible(selected)
            }
            .onChange(of: scenePhase) { _, phase in
                viewModel.onScenePhase(phase)
            }
            .sheet(item: $viewModel.shareItem, onDismiss: {
                // Cleanup uses shareCleanupDirectory (not shareItem, which is already nil here).
                viewModel.dismissShare()
            }) { item in
                ActivityShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Sections

    private var composeSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("粘贴视频链接", text: $viewModel.urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)

                Button {
                    viewModel.pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("粘贴")
            }

            FormatChipBar(
                presets: YTFormatOption.presets,
                selection: $viewModel.selectedPreset
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.parseURL() }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isParsing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("解析")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.accentColor)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.isParsing || viewModel.isEnqueueing)

                Button {
                    Task { await viewModel.startDownload() }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isEnqueueing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text("开始下载")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(
                        Color.accentColor,
                        in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.isParsing || viewModel.isEnqueueing)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("新建下载")
        } footer: {
            if !settings.isYTConfigured {
                Text("请先在「设置」中填写下载服务账号密码。")
            }
        }
    }

    private func metadataSection(_ meta: VideoMetadata) -> some View {
        Section("视频信息") {
            VStack(alignment: .leading, spacing: 6) {
                Text(meta.title)
                    .font(.body.weight(.semibold))
                HStack(spacing: 12) {
                    if let uploader = meta.uploader, !uploader.isEmpty {
                        Label(uploader, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let duration = meta.duration, !duration.isEmpty {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var tasksSection: some View {
        Section {
            if viewModel.tasks.isEmpty {
                Text("暂无下载任务")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.tasks) { task in
                    TaskRowView(
                        task: task,
                        isSharing: viewModel.downloadingPath == task.filepath,
                        onKill: {
                            Task { await viewModel.kill(task) }
                        },
                        onClear: {
                            Task { await viewModel.clear(task) }
                        },
                        onShare: {
                            guard let path = task.filepath else { return }
                            Task {
                                await viewModel.prepareShare(
                                    path: path,
                                    suggestedName: (path as NSString).lastPathComponent
                                )
                            }
                        }
                    )
                }
            }
        } header: {
            HStack {
                Text("任务队列")
                Spacer()
                Text("\(viewModel.tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filesSection: some View {
        Section {
            FilesListView(
                files: viewModel.files,
                downloadingPath: viewModel.downloadingPath,
                onShare: { file in
                    Task {
                        await viewModel.prepareShare(path: file.path, suggestedName: file.name)
                    }
                },
                onDelete: { file in
                    Task { await viewModel.deleteFile(file) }
                }
            )
        } header: {
            HStack {
                Text("已完成文件")
                Spacer()
                Text("\(viewModel.files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bannerRow(text: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: color == .red ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Format chips

struct FormatChipBar: View {
    let presets: [YTFormatOption]
    @Binding var selection: YTFormatOption

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    let selected = selection.id == preset.id
                    Button {
                        selection = preset
                        Haptics.light()
                    } label: {
                        Text(preset.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                selected ? Color.accentColor : Color(.tertiarySystemFill),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - UIActivityViewController wrapper

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    DownloadHomeView()
        .environmentObject(AppSettings.shared)
}
