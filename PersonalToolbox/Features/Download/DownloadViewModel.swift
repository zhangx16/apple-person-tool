import Foundation
import SwiftUI
import Combine
import UIKit

/// Drives the Download tab: URL parse/start, 2s queue poll, file list, share.
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
    @Published private(set) var downloadingPath: String?

    private let settings: AppSettings
    private let service = YTService.shared
    private var pollTask: Task<Void, Never>?
    /// Driven by RootTabView selection (more reliable than onAppear/onDisappear under TabView).
    private var isTabVisible = false
    private var sceneActive = true
    private var lastFilesRefresh: Date = .distantPast
    private let filesThrottle: TimeInterval = 4
    /// Survives sheet `item` nil-ing so onDismiss can always delete the staged UUID directory.
    private var shareCleanupDirectory: URL?

    init(settings: AppSettings = .shared) {
        self.settings = settings
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
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            errorBanner = "请输入视频链接"
            Haptics.error()
            return
        }
        guard isConfigured else {
            errorBanner = "请先在设置中配置下载服务"
            Haptics.error()
            return
        }
        isParsing = true
        errorBanner = nil
        defer { isParsing = false }
        do {
            let meta = try await service.parseFormats(
                baseURL: baseURL,
                username: username,
                password: password,
                url: url
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
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            errorBanner = "请输入视频链接"
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
                url: url,
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

    func kill(_ task: YTTask) async {
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
    /// On 401, force re-login and retry the download once.
    func prepareShare(path: String, suggestedName: String?) async {
        guard isConfigured else {
            errorBanner = "请先在设置中配置下载服务"
            return
        }
        downloadingPath = path
        defer { downloadingPath = nil }
        do {
            try await stageShareFile(path: path, suggestedName: suggestedName)
            Haptics.success()
        } catch {
            if Self.isUnauthorized(error) {
                // File download sits outside withAuthRetry — re-login and retry once.
                await service.logout()
                do {
                    try await stageShareFile(path: path, suggestedName: suggestedName)
                    Haptics.success()
                    return
                } catch {
                    errorBanner = Self.chineseError(error)
                    Haptics.error()
                    return
                }
            }
            errorBanner = Self.chineseError(error)
            Haptics.error()
        }
    }

    private func stageShareFile(path: String, suggestedName: String?) async throws {
        // Drop any previous staged share before creating a new temp dir.
        cleanupShareDirectory()

        try await service.ensureLogin(baseURL: baseURL, username: username, password: password)
        let remote = try await service.downloadURL(baseURL: baseURL, path: path)
        // Token stays on the URLSession request only — never handed to Share sheet.
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
        shareItem = ShareableFile(url: dest, name: name)
    }

    /// Always safe to call from sheet onDismiss — uses `shareCleanupDirectory`, not `shareItem`.
    func dismissShare() {
        cleanupShareDirectory()
        shareItem = nil
    }

    private func cleanupShareDirectory() {
        if let dir = shareCleanupDirectory {
            try? FileManager.default.removeItem(at: dir)
            shareCleanupDirectory = nil
        }
    }

    // MARK: - Refresh

    func refreshNow(silent: Bool = false) async {
        guard isConfigured else {
            if !silent {
                errorBanner = "请先在设置中配置下载服务"
            }
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
            tasks = nextTasks

            let now = Date()
            let needFiles = !silent
                || now.timeIntervalSince(lastFilesRefresh) >= filesThrottle
                || nextTasks.contains(where: { $0.isCompleted })
            if needFiles {
                let nextFiles = try await service.listFiles(
                    baseURL: baseURL,
                    username: username,
                    password: password
                )
                files = nextFiles
                lastFilesRefresh = now
            }
            reevaluatePolling()
        } catch {
            if !silent {
                errorBanner = Self.chineseError(error)
            }
            // Keep polling on transient errors; token refresh is handled inside YTService.
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
