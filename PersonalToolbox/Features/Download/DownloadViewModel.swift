import Foundation
import SwiftUI
import Combine
import UIKit

/// Drives the Download tab: URL parse/start, 2s queue poll, file list, share.
/// Douyin share links are handled locally via `DouyinService`; other URLs go to yt-dlp-web-ui.
@MainActor
final class DownloadViewModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var selectedPreset: YTFormatOption = YTFormatOption.presets[0]
    @Published private(set) var metadata: VideoMetadata?
    @Published private(set) var tasks: [YTTask] = []
    @Published private(set) var files: [YTFileItem] = []
    @Published private(set) var isParsing = false
    @Published private(set) var isEnqueueing = false
    @Published private(set) var isRefreshing = false
    @Published var errorBanner: String?
    @Published var infoBanner: String?
    /// Local file URL ready for Share sheet (token stripped; temp sandbox file).
    @Published var shareItem: ShareableFile?
    /// Local file ready for system AVPlayer sheet.
    @Published var playItem: ShareableFile?
    @Published private(set) var downloadingPath: String?
    /// True when staging a remote file for playback (reuses downloadingPath).
    @Published private(set) var playingPath: String?
    /// Live log lines for the current Douyin job (newest last).
    @Published private(set) var douyinLogs: [String] = []
    @Published private(set) var douyinStage: String = ""
    /// Explicit project selected via nav title menu (YouTube service vs Douyin local).
    @Published var project: DownloadProject = .youtube
    /// Douyin video quality preference (aligned with douyin-downloader).
    @Published var douyinQuality: DouyinService.VideoQuality = .highest

    private let settings: AppSettings
    private let service = YTService.shared
    private let douyin = DouyinService.shared
    private var pollTask: Task<Void, Never>?
    /// Driven by RootTabView selection (more reliable than onAppear/onDisappear under TabView).
    private var isTabVisible = false
    private var sceneActive = true
    private var lastFilesRefresh: Date = .distantPast
    private let filesThrottle: TimeInterval = 4
    /// Survives sheet `item` nil-ing so onDismiss can always delete the staged UUID directory.
    private var shareCleanupDirectory: URL?
    /// Local Douyin tasks kept separate from remote queue, then merged for UI.
    private var localTasks: [YTTask] = []
    private var remoteTasks: [YTTask] = []
    private var activeDouyinWork: Task<Void, Never>?
    private var cancelledDouyinIds: Set<String> = []
    /// Previous processStatus by remote task id — detect transitions to completed/failed.
    private var lastRemoteStatus: [String: Int] = [:]
    private var hasSeededRemoteStatus = false

    init(settings: AppSettings = .shared) {
        self.settings = settings
        if let p = DownloadProject(rawValue: settings.downloadProjectRaw) {
            project = p
        }
    }

    /// Manual project mode from title menu. Auto-detect still applies as soft hint only when youtube mode gets a douyin URL.
    var isDouyinMode: Bool { project == .douyin }

    func setProject(_ newProject: DownloadProject) {
        guard project != newProject else { return }
        project = newProject
        settings.downloadProjectRaw = newProject.rawValue
        metadata = nil
        douyinLogs = []
        douyinStage = ""
        errorBanner = nil
        // Soft notice when switching.
        if newProject == .douyin {
            infoBanner = "已切换到抖音本机下载"
        } else {
            infoBanner = "已切换到 YouTube / yt-dlp 服务下载"
        }
    }

    func syncProjectFromSettings() {
        if let p = DownloadProject(rawValue: settings.downloadProjectRaw), p != project {
            project = p
            metadata = nil
            douyinLogs = []
            douyinStage = ""
        }
    }

    // MARK: - Lifecycle / polling

    /// Called when Download tab selection changes (preferred over view appear/disappear).
    func setTabVisible(_ visible: Bool) {
        let wasVisible = isTabVisible
        isTabVisible = visible
        if visible {
            if !wasVisible {
                Task { await refreshNow() }
            }
            startPollingIfNeeded()
        } else if !tasks.contains(where: \.isActive) {
            stopPolling()
        }
    }

    func onScenePhase(_ phase: ScenePhase) {
        sceneActive = (phase == .active)
        if sceneActive {
            Task { await refreshNow() }
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
    }

    private var shouldPoll: Bool {
        sceneActive && (isTabVisible || tasks.contains(where: \.isActive))
    }

    private func startPollingIfNeeded() {
        guard shouldPoll else {
            stopPolling()
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { break }
                guard self.shouldPoll else {
                    self.stopPolling()
                    break
                }
                await self.refreshNow(silent: true)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func reevaluatePolling() {
        if shouldPoll {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
    }

    // MARK: - Credentials

    private var baseURL: String {
        settings.ytBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var username: String {
        settings.ytUsername.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var password: String { settings.ytPassword }

    private var isConfigured: Bool {
        !baseURL.isEmpty && !username.isEmpty && !password.isEmpty
    }

    // MARK: - Actions

    func pasteFromClipboard() {
        #if canImport(UIKit)
        if let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            urlText = s
            Haptics.light()
        }
        #endif
    }

    func parseURL() async {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            errorBanner = "请输入视频链接"
            Haptics.error()
            return
        }

        isParsing = true
        errorBanner = nil
        douyinLogs = []
        douyinStage = ""
        defer { isParsing = false }

        if isDouyinMode {
            do {
                let url = DouyinService.extractURL(from: raw) ?? raw
                let meta = try await douyin.parseMetadata(sourceURL: url) { [weak self] line in
                    self?.appendDouyinLog(line)
                }
                metadata = meta
                infoBanner = "抖音解析完成"
                Haptics.success()
            } catch {
                metadata = nil
                errorBanner = Self.chineseError(error)
                Haptics.error()
            }
            return
        }

        // YouTube / yt-dlp mode: if user pasted a Douyin URL, nudge them to switch.
        if DouyinService.isDouyinURL(DouyinService.extractURL(from: raw) ?? raw) {
            errorBanner = "这是抖音链接。请点顶部标题切换到「抖音」后再下载。"
            Haptics.error()
            return
        }

        guard isConfigured else {
            errorBanner = "请先在设置中配置下载服务"
            Haptics.error()
            return
        }
        do {
            let meta = try await service.parseFormats(
                baseURL: baseURL,
                username: username,
                password: password,
                url: raw
            )
            metadata = meta
            Haptics.success()
        } catch {
            metadata = nil
            errorBanner = Self.chineseError(error)
            Haptics.error()
        }
    }

    func startDownload() async {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            errorBanner = "请输入视频链接"
            Haptics.error()
            return
        }

        if isDouyinMode {
            await startDouyinDownload(raw: raw)
            return
        }

        if DouyinService.isDouyinURL(DouyinService.extractURL(from: raw) ?? raw) {
            errorBanner = "这是抖音链接。请点顶部标题切换到「抖音」后再下载。"
            Haptics.error()
            return
        }

        guard isConfigured else {
            errorBanner = "请先在设置中配置下载服务"
            Haptics.error()
            return
        }
        isEnqueueing = true
        errorBanner = nil
        defer { isEnqueueing = false }
        do {
            try await service.startDownload(
                baseURL: baseURL,
                username: username,
                password: password,
                url: raw,
                preset: selectedPreset
            )
            infoBanner = "已加入下载队列"
            Haptics.success()
            await refreshNow()
            startPollingIfNeeded()
        } catch {
            errorBanner = Self.chineseError(error)
            Haptics.error()
        }
    }

    private func startDouyinDownload(raw: String) async {
        // Cancel any in-flight Douyin job so only one runs at a time.
        activeDouyinWork?.cancel()

        isEnqueueing = true
        errorBanner = nil
        douyinLogs = []
        douyinStage = "准备中"

        let url = DouyinService.extractURL(from: raw) ?? raw
        let taskId = UUID().uuidString
        cancelledDouyinIds.remove(taskId)
        upsertLocalTask(
            YTTask.makeLocalDouyin(
                id: taskId,
                url: url,
                title: metadata?.title ?? "抖音下载",
                processStatus: 1,
                progress: 0.02,
                stage: "解析中"
            )
        )

        let work = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isEnqueueing = false
                    self.activeDouyinWork = nil
                    self.reevaluatePolling()
                }
            }
            do {
                let result = try await self.douyin.download(
                    sourceURL: url,
                    preferNoWatermark: true,
                    quality: self.douyinQuality,
                    onProgress: { fraction, stage in
                        Task { @MainActor in
                            guard !self.cancelledDouyinIds.contains(taskId) else { return }
                            self.douyinStage = stage
                            self.upsertLocalTask(
                                YTTask.makeLocalDouyin(
                                    id: taskId,
                                    url: url,
                                    title: self.metadata?.title ?? stage,
                                    processStatus: 1,
                                    progress: fraction,
                                    stage: stage
                                )
                            )
                        }
                    },
                    onLog: { line in
                        Task { @MainActor in
                            guard !self.cancelledDouyinIds.contains(taskId) else { return }
                            self.appendDouyinLog(line)
                        }
                    }
                )
                await MainActor.run {
                    guard !self.cancelledDouyinIds.contains(taskId) else { return }
                    self.metadata = VideoMetadata(
                        title: result.title,
                        duration: nil,
                        thumbnail: result.thumbnailURL,
                        uploader: nil
                    )
                    self.upsertLocalTask(
                        YTTask.makeLocalDouyin(
                            id: taskId,
                            url: url,
                            title: result.title,
                            processStatus: 2,
                            progress: 1,
                            stage: "已完成 · \(result.matchedCandidateLabel)",
                            filepath: result.filePath
                        )
                    )
                    self.infoBanner = "抖音下载完成：\(result.fileName)"
                    Haptics.success()
                    self.mergeLocalFilesIntoList()
                    self.emitDownloadNotificationIfNeeded(
                        taskId: taskId,
                        title: result.title,
                        source: "抖音",
                        failed: false,
                        reason: nil
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.localTasks.removeAll { $0.id == YTTask.localDouyinPrefix + taskId }
                    self.rebuildTasks()
                }
            } catch {
                await MainActor.run {
                    guard !self.cancelledDouyinIds.contains(taskId) else { return }
                    let reason = Self.chineseError(error)
                    self.upsertLocalTask(
                        YTTask.makeLocalDouyin(
                            id: taskId,
                            url: url,
                            title: self.metadata?.title ?? "抖音下载",
                            processStatus: 3,
                            progress: 0,
                            stage: "失败",
                            error: reason
                        )
                    )
                    self.errorBanner = reason
                    Haptics.error()
                    self.emitDownloadNotificationIfNeeded(
                        taskId: taskId,
                        title: self.metadata?.title ?? "抖音下载",
                        source: "抖音",
                        failed: true,
                        reason: reason
                    )
                }
            }
        }
        activeDouyinWork = work
        await work.value
    }

    private func appendDouyinLog(_ line: String) {
        douyinLogs.append(line)
        if douyinLogs.count > 80 {
            douyinLogs.removeFirst(douyinLogs.count - 80)
        }
    }

    private func upsertLocalTask(_ task: YTTask) {
        if let idx = localTasks.firstIndex(where: { $0.id == task.id }) {
            localTasks[idx] = task
        } else {
            localTasks.insert(task, at: 0)
        }
        // Keep at most 20 local history rows.
        if localTasks.count > 20 {
            localTasks = Array(localTasks.prefix(20))
        }
        rebuildTasks()
    }

    private func rebuildTasks() {
        // Local active/recent first, then remote queue.
        tasks = localTasks + remoteTasks
    }

    private func mergeLocalFilesIntoList() {
        let local = douyin.listLocalFiles()
        // Prefer showing local files; remote files loaded separately.
        let remoteOnly = files.filter { !$0.isLocalFile && !$0.id.hasPrefix("local:") }
        files = local + remoteOnly
    }

    func kill(_ task: YTTask) async {
        if task.isLocalDouyin {
            let rawId = String(task.id.dropFirst(YTTask.localDouyinPrefix.count))
            cancelledDouyinIds.insert(rawId)
            if task.isActive {
                activeDouyinWork?.cancel()
                activeDouyinWork = nil
                isEnqueueing = false
            }
            localTasks.removeAll { $0.id == task.id }
            rebuildTasks()
            Haptics.light()
            return
        }
        guard isConfigured else { return }
        do {
            try await service.killTask(
                baseURL: baseURL,
                username: username,
                password: password,
                id: task.id
            )
            Haptics.light()
            await refreshNow()
        } catch {
            errorBanner = Self.chineseError(error)
            Haptics.error()
        }
    }

    func clear(_ task: YTTask) async {
        if task.isLocalDouyin {
            localTasks.removeAll { $0.id == task.id }
            rebuildTasks()
            Haptics.light()
            return
        }
        guard isConfigured else { return }
        do {
            try await service.clearTask(
                baseURL: baseURL,
                username: username,
                password: password,
                id: task.id
            )
            Haptics.light()
            await refreshNow()
        } catch {
            errorBanner = Self.chineseError(error)
            Haptics.error()
        }
    }

    func deleteFile(_ file: YTFileItem) async {
        if file.isLocalFile || file.id.hasPrefix("local:") {
            do {
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(atPath: file.path)
                }
                files.removeAll { $0.id == file.id }
                Haptics.success()
            } catch {
                errorBanner = Self.chineseError(error)
                Haptics.error()
            }
            return
        }
        guard isConfigured else { return }
        do {
            try await service.deleteFile(
                baseURL: baseURL,
                username: username,
                password: password,
                path: file.path
            )
            files.removeAll { $0.id == file.id }
            Haptics.success()
        } catch {
            errorBanner = Self.chineseError(error)
            Haptics.error()
        }
    }

    /// Download remote file into sandbox temp, then present Share sheet (no token in shared URL).
    /// Local Douyin files are shared directly from Documents.
    /// On 401, force re-login and retry the download once.
    func prepareShare(path: String, suggestedName: String?) async {
        downloadingPath = path
        defer { downloadingPath = nil }

        do {
            let staged = try await stageLocalFile(path: path, suggestedName: suggestedName, forPlay: false)
            shareItem = staged
            Haptics.success()
        } catch {
            errorBanner = Self.chineseError(error)
            Haptics.error()
        }
    }

    /// Stage a local/remote file and present the system video player.
    func preparePlay(path: String, suggestedName: String?) async {
        let name = suggestedName ?? (path as NSString).lastPathComponent
        guard DownloadMediaKind.detect(pathOrName: name).isPlayableVideo
                || DownloadMediaKind.detect(pathOrName: path).isPlayableVideo else {
            errorBanner = "该文件不是可播放的视频格式"
            Haptics.error()
            return
        }

        playingPath = path
        downloadingPath = path
        defer {
            playingPath = nil
            downloadingPath = nil
        }

        do {
            let staged = try await stageLocalFile(path: path, suggestedName: suggestedName, forPlay: true)
            playItem = staged
            Haptics.success()
        } catch {
            errorBanner = Self.chineseError(error)
            Haptics.error()
        }
    }

    /// Resolve a sandbox file URL for share/play. Remote paths are downloaded with auth.
    private func stageLocalFile(path: String, suggestedName: String?, forPlay: Bool) async throws -> ShareableFile {
        // Local absolute path (Douyin sandbox / already staged).
        if FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let name = suggestedName ?? url.lastPathComponent
            // Playing local files does not use share cleanup dir.
            if !forPlay {
                shareCleanupDirectory = nil
            }
            return ShareableFile(url: url, name: name)
        }

        guard isConfigured else {
            throw NetworkError.message("请先在设置中配置下载服务")
        }

        do {
            return try await downloadRemoteToTemp(path: path, suggestedName: suggestedName)
        } catch {
            if Self.isUnauthorized(error) {
                await service.logout()
                return try await downloadRemoteToTemp(path: path, suggestedName: suggestedName)
            }
            throw error
        }
    }

    private func downloadRemoteToTemp(path: String, suggestedName: String?) async throws -> ShareableFile {
        // Drop any previous staged share before creating a new temp dir.
        cleanupShareDirectory()

        try await service.ensureLogin(baseURL: baseURL, username: username, password: password)
        let remote = try await service.downloadURL(baseURL: baseURL, path: path)
        // Token stays on the URLSession request only — never handed to Share sheet / player as remote URL.
        let (tempURL, response) = try await URLSession.shared.download(from: remote)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw NetworkError.unauthorized
            }
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkError.http(http.statusCode, "下载失败")
            }
        }
        let name = suggestedName
            ?? (path as NSString).lastPathComponent
            .ifEmpty("download.bin")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dest = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        // Remember dir independently of shareItem so sheet onDismiss still cleans up
        // after SwiftUI has already nil'd the item binding.
        shareCleanupDirectory = dir
        return ShareableFile(url: dest, name: name)
    }

    /// Always safe to call from share sheet onDismiss — uses `shareCleanupDirectory`, not `shareItem`.
    func dismissShare() {
        cleanupShareDirectory()
        shareItem = nil
    }

    /// Dismiss player; clean temp if it was a staged remote download.
    func dismissPlay() {
        // Only remove temp staging when play item lives under the cleanup directory.
        if let play = playItem, let dir = shareCleanupDirectory,
           play.url.path.hasPrefix(dir.path) {
            cleanupShareDirectory()
        }
        playItem = nil
    }

    private func cleanupShareDirectory() {
        if let dir = shareCleanupDirectory {
            try? FileManager.default.removeItem(at: dir)
            shareCleanupDirectory = nil
        }
    }

    // MARK: - Refresh

    func refreshNow(silent: Bool = false) async {
        // Always surface local Douyin files even when remote service is not configured.
        mergeLocalFilesIntoList()

        guard isConfigured else {
            rebuildTasks()
            // Soft notice only on explicit refresh, and only if not currently on a Douyin URL.
            if !silent && !isDouyinMode && errorBanner == nil && infoBanner == nil {
                infoBanner = "通用下载需配置 yt-dlp 服务；抖音链接可直接粘贴本机下载"
            }
            reevaluatePolling()
            return
        }
        if !silent { isRefreshing = true }
        defer { if !silent { isRefreshing = false } }

        do {
            let nextTasks = try await service.runningTasks(
                baseURL: baseURL,
                username: username,
                password: password
            )
            detectRemoteTaskTransitions(nextTasks)
            remoteTasks = nextTasks
            rebuildTasks()

            let now = Date()
            let needFiles = !silent
                || now.timeIntervalSince(lastFilesRefresh) >= filesThrottle
                || nextTasks.contains(where: { $0.isCompleted })
            if needFiles {
                let remoteFiles = try await service.listFiles(
                    baseURL: baseURL,
                    username: username,
                    password: password
                )
                let local = douyin.listLocalFiles()
                files = local + remoteFiles
                lastFilesRefresh = now
            }
            reevaluatePolling()
        } catch {
            rebuildTasks()
            if !silent {
                errorBanner = Self.chineseError(error)
            }
            // Keep polling on transient errors; token refresh is handled inside YTService.
        }
    }

    /// Notify when remote queue tasks flip from pending/running → completed/failed.
    private func detectRemoteTaskTransitions(_ nextTasks: [YTTask]) {
        if !hasSeededRemoteStatus {
            // First snapshot only seeds baseline — avoid notifying historical completed jobs.
            for task in nextTasks {
                lastRemoteStatus[task.id] = task.processStatus
            }
            hasSeededRemoteStatus = true
            return
        }

        for task in nextTasks {
            let prev = lastRemoteStatus[task.id]
            lastRemoteStatus[task.id] = task.processStatus
            let wasActive = prev == 0 || prev == 1
            // Also treat newly-seen active→complete within same session when prev nil after seed? skip
            guard wasActive else { continue }
            if task.isCompleted {
                emitDownloadNotificationIfNeeded(
                    taskId: task.id,
                    title: task.title.isEmpty ? task.url : task.title,
                    source: "YouTube",
                    failed: false,
                    reason: nil
                )
            } else if task.isFailed {
                emitDownloadNotificationIfNeeded(
                    taskId: task.id,
                    title: task.title.isEmpty ? task.url : task.title,
                    source: "YouTube",
                    failed: true,
                    reason: task.error
                )
            }
        }

        // Drop statuses for tasks no longer in the queue.
        let live = Set(nextTasks.map(\.id))
        lastRemoteStatus = lastRemoteStatus.filter { live.contains($0.key) }
    }

    private func emitDownloadNotificationIfNeeded(
        taskId: String,
        title: String,
        source: String,
        failed: Bool,
        reason: String?
    ) {
        guard settings.notifyDownloadCompleted else { return }
        Task {
            let ok = await LocalNotifier.ensureAuthorized()
            guard ok else { return }
            if failed {
                LocalNotifier.notifyDownloadFailed(
                    taskId: taskId,
                    title: title,
                    source: source,
                    reason: reason
                )
            } else {
                LocalNotifier.notifyDownloadCompleted(
                    taskId: taskId,
                    title: title,
                    source: source
                )
            }
        }
    }

    // MARK: - Helpers

    static func isUnauthorized(_ error: Error) -> Bool {
        if let net = error as? NetworkError {
            switch net {
            case .unauthorized: return true
            case .http(let code, _): return code == 401
            default: return false
            }
        }
        return false
    }

    static func chineseError(_ error: Error) -> String {
        if let net = error as? NetworkError {
            return net.errorDescription ?? "网络错误"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "无网络连接"
            case NSURLErrorTimedOut: return "请求超时"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "无法连接服务器"
            case NSURLErrorSecureConnectionFailed: return "安全连接失败"
            default: break
            }
        }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "未知错误" : text
    }
}

/// Wrapper so sheet(item:) can present a sandbox file for sharing.
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
