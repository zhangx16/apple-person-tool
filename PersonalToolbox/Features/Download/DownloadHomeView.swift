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
                if viewModel.isDouyinMode, !viewModel.douyinLogs.isEmpty || !viewModel.douyinStage.isEmpty {
                    douyinLogSection
                }
                tasksSection
                filesSection
            }
            .listStyle(.insetGrouped)
            .background(AppleTheme.canvas)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DownloadNavTitle(selection: Binding(
                        get: { viewModel.project },
                        set: { viewModel.setProject($0) }
                    ))
                }
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
                viewModel.syncProjectFromSettings()
                viewModel.setTabVisible(isTabSelected)
                viewModel.onScenePhase(scenePhase)
            }
            .onChange(of: isTabSelected) { _, selected in
                if selected {
                    viewModel.syncProjectFromSettings()
                }
                viewModel.setTabVisible(selected)
            }
            .onChange(of: settings.downloadProjectRaw) { _, _ in
                viewModel.syncProjectFromSettings()
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
            .fullScreenCover(item: $viewModel.playItem, onDismiss: {
                viewModel.dismissPlay()
            }) { item in
                VideoPlayerSheet(url: item.url, title: item.name)
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

            // Quality presets only apply to YouTube / yt-dlp backend.
            if !viewModel.isDouyinMode {
                FormatChipBar(
                    presets: YTFormatOption.presets,
                    selection: $viewModel.selectedPreset
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

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
                    .frame(minHeight: 44)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.accentColor)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.isParsing || viewModel.isEnqueueing)
                .accessibilityLabel("解析链接")
                .accessibilityHint(viewModel.isDouyinMode ? "本机解析抖音标题" : "获取视频标题与格式信息")

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
                        Text(viewModel.isDouyinMode ? "本机下载" : "开始下载")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(
                        Color.accentColor,
                        in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.isParsing || viewModel.isEnqueueing)
                .accessibilityLabel(viewModel.isDouyinMode ? "本机下载抖音" : "开始下载")
                .accessibilityHint(
                    viewModel.isDouyinMode
                        ? "使用 WebView 解析并下载到本机"
                        : "按所选画质加入下载队列"
                )
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text(viewModel.isDouyinMode ? "新建抖音下载" : "新建 YouTube 下载")
        } footer: {
            if viewModel.isDouyinMode {
                Text("粘贴 v.douyin.com / douyin.com 分享链接或分享文案。优先无水印，文件保存在本机 Documents/douyin-downloader。点顶部标题可切回 YouTube。")
            } else if !settings.isYTConfigured {
                Text("请先在「设置」中填写 yt-dlp 下载服务账号密码。抖音请点顶部标题切换到「抖音」。")
            } else {
                Text("通过 yt-dlp 服务下载 YouTube 等通用链接。抖音请点顶部标题切换到「抖音」。")
            }
        }
    }

    private var douyinLogSection: some View {
        Section {
            if !viewModel.douyinStage.isEmpty {
                Text(viewModel.douyinStage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            if !viewModel.douyinLogs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.douyinLogs.suffix(12).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("抖音解析日志")
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
                        },
                        onPlay: {
                            guard let path = task.filepath else { return }
                            Task {
                                await viewModel.preparePlay(
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
                onPlay: { file in
                    Task {
                        await viewModel.preparePlay(path: file.path, suggestedName: file.name)
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
        let isError = color == .red
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(isError ? "错误：\(text)" : text)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭提示")
        }
        .padding(.vertical, 4)
        // Keep dismiss as its own VO target (do not combine into static text).
        .accessibilityElement(children: .contain)
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
                        // Selection feedback only — no continuous scroll haptics (DESIGN §3.8).
                    } label: {
                        Text(preset.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                selected ? Color.accentColor : Color(.tertiarySystemFill),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(preset.label)
                    .accessibilityHint("画质预设")
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("画质")
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
