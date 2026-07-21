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
            if viewModel.isLocalMode, !viewModel.douyinLogs.isEmpty || !viewModel.douyinStage.isEmpty {
                douyinLogSection
            }
            tasksSection
            filesSection
        }
        .listStyle(.insetGrouped)
        .background(AppSurfaceBackground(accent: ServiceBrand.youtube.tint))
        // 统一「视频下载」模块：YouTube / 抖音 / B站 均为页内切换，不单独占底部 Tab
        .navigationTitle("视频下载")
        .navigationBarTitleDisplayMode(.large)
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
            viewModel.dismissShare()
        }) { item in
            ActivityShareSheet(items: [item.url])
        }
        .fullScreenCover(item: $viewModel.playItem, onDismiss: {
            viewModel.dismissPlay()
            // Safety: always restore portrait when the player cover is dismissed.
            OrientationHelper.lockPortrait()
        }) { item in
            VideoPlayerSheet(url: item.url, title: item.name)
                .onAppear { OrientationHelper.lockLandscape() }
        }
    }

    // MARK: - Sections

    private var composeSection: some View {
        Section {
            // 同一模块内切换来源（非底部 Tab）
            platformPicker

            HStack(spacing: 8) {
                TextField(linkPlaceholder, text: $viewModel.urlText)
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

            // Quality presets by project.
            if viewModel.isDouyinMode {
                qualityChips(
                    items: DouyinService.VideoQuality.allCases.map { ($0.rawValue, $0) },
                    selected: viewModel.douyinQuality
                ) { viewModel.douyinQuality = $0 }
            } else if viewModel.isBilibiliMode {
                qualityChips(
                    items: [
                        ("1080P", 80),
                        ("720P", 64),
                        ("480P", 32),
                        ("360P", 16)
                    ],
                    selected: viewModel.bilibiliQn
                ) { viewModel.bilibiliQn = $0 }
                if viewModel.bilibiliPages.count > 1 {
                    Picker("分 P", selection: $viewModel.bilibiliPageIndex) {
                        ForEach(Array(viewModel.bilibiliPages.enumerated()), id: \.element.id) { idx, page in
                            Text("P\(page.page) \(page.part.isEmpty ? "" : page.part)")
                                .tag(idx)
                        }
                    }
                }
            } else {
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
                .accessibilityHint(viewModel.isLocalMode ? "本机解析标题" : "获取视频标题与格式信息")

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
                        Text(viewModel.isLocalMode ? "本机下载" : "开始下载")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(
                        Color.accentColor.brandGradient,
                        in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous)
                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                    }
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 8, y: 3)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.isParsing || viewModel.isEnqueueing)
                .accessibilityLabel(viewModel.isLocalMode ? "本机下载" : "开始下载")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("新建下载")
        } footer: {
            Text(composeFooter)
                .font(.caption)
        }
    }

    private var platformPicker: some View {
        HStack(spacing: 8) {
            ForEach(DownloadProject.allCases) { p in
                let on = viewModel.project == p
                Button {
                    viewModel.setProject(p)
                } label: {
                    HStack(spacing: 6) {
                        ServiceBrandIcon(brand: p.brand, size: 18, showsBackground: false)
                        Text(p.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(
                        on ? AnyShapeStyle(p.brand.tint.brandGradient) : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        if on {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                        }
                    }
                    .shadow(color: on ? p.brand.tint.opacity(0.3) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98))
                .accessibilityLabel(p.accessibilityLabel)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private var linkPlaceholder: String {
        switch viewModel.project {
        case .youtube: return "粘贴 YouTube 等链接"
        case .douyin: return "粘贴抖音分享链接"
        case .bilibili: return "粘贴 BV / b23.tv 链接"
        }
    }

    private var composeFooter: String {
        switch viewModel.project {
        case .douyin:
            return "粘贴抖音分享链接。短链展开、无水印与画质参考 douyin-downloader。Cookie：设置 → 抖音。"
        case .bilibili:
            return "粘贴 BV/av/b23.tv 链接。本机 playurl 下载（参考 BilibiliDown）。高清建议配置 SESSDATA。文件：Documents/bilibili-downloader。"
        case .youtube:
            return settings.isYTConfigured
                ? "通过 yt-dlp 服务下载通用链接。抖音/B站请切换顶部模式。"
                : "请先在设置中配置 yt-dlp。抖音/B站可本机下载。"
        }
    }

    private func qualityChips<T: Hashable>(
        items: [(String, T)],
        selected: T,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let on = selected == item.1
                    Button {
                        onSelect(item.1)
                    } label: {
                        Text(item.0)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(
                                on ? Color.accentColor : Color(.tertiarySystemFill),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
            Text(viewModel.isBilibiliMode ? "B站解析日志" : "抖音解析日志")
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
