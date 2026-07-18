import Foundation
import SwiftData
import Combine
import UIKit

/// Drives Grok Imagine compose sheet: 生图 / 编辑 / 视频.
@MainActor
final class ImagineViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case image
        case edit
        case video

        var id: String { rawValue }

        var title: String {
            switch self {
            case .image: return "生图"
            case .edit: return "编辑"
            case .video: return "视频"
            }
        }
    }

    @Published var mode: Mode = .image
    @Published var prompt: String = ""
    @Published var selectedImageData: Data?
    @Published var isRunning: Bool = false
    @Published var progressNote: String?
    @Published var errorMessage: String?
    @Published var imageModel: String = AppSettings.defaultImagineImageModel
    @Published var editModel: String = AppSettings.defaultImagineEditModel
    @Published var videoModel: String = AppSettings.defaultImagineVideoModel
    @Published var availableImageModels: [String] = AppSettings.defaultImagineImageModels
    @Published var availableEditModels: [String] = AppSettings.defaultImagineEditModels
    @Published var availableVideoModels: [String] = AppSettings.defaultImagineVideoModels

    private var store: ConversationStore?
    private var settings: AppSettings
    private let service = ImagineService.shared
    private let listService = Sub2APIService.shared
    private var runTask: Task<Void, Never>?
    private var didAttach = false

    /// Called after media is inserted so the thread can refresh.
    var onConversationUpdated: ((UUID) -> Void)?

    init(settings: AppSettings = .shared) {
        self.settings = settings
        imageModel = settings.preferredImagineImageModel
        editModel = settings.preferredImagineEditModel
        videoModel = settings.preferredImagineVideoModel
    }

    func attach(modelContext: ModelContext, settings: AppSettings = .shared) {
        self.settings = settings
        if !didAttach || store == nil {
            store = ConversationStore(modelContext: modelContext)
            didAttach = true
        }
        imageModel = settings.preferredImagineImageModel
        editModel = settings.preferredImagineEditModel
        videoModel = settings.preferredImagineVideoModel
    }

    var canSubmit: Bool {
        guard !isRunning else { return false }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if mode == .edit, selectedImageData == nil { return false }
        return settings.isAIConfigured
    }

    // MARK: Models

    func loadModels() async {
        guard settings.isAIConfigured else {
            availableImageModels = AppSettings.defaultImagineImageModels
            availableEditModels = AppSettings.defaultImagineEditModels
            availableVideoModels = AppSettings.defaultImagineVideoModels
            return
        }
        do {
            let remote = try await listService.listModels(
                baseURL: settings.sub2apiBaseURL,
                apiKey: settings.sub2apiAPIKey
            )
            let imagine = remote.filter { Sub2APIService.isImagineModel($0) }
            var images = Set(AppSettings.defaultImagineImageModels)
            var edits = Set(AppSettings.defaultImagineEditModels)
            var videos = Set(AppSettings.defaultImagineVideoModels)
            for id in imagine {
                if Sub2APIService.isImagineVideoModel(id) {
                    videos.insert(id)
                } else if Sub2APIService.isImagineEditModel(id) {
                    edits.insert(id)
                } else if Sub2APIService.isImagineImageModel(id) {
                    images.insert(id)
                } else {
                    // Generic "grok-imagine" etc. → image list
                    images.insert(id)
                }
            }
            images.insert(imageModel)
            edits.insert(editModel)
            videos.insert(videoModel)
            availableImageModels = images.sorted()
            availableEditModels = edits.sorted()
            availableVideoModels = videos.sorted()
        } catch {
            // Keep defaults on failure.
        }
    }

    // MARK: Generate

    /// Target conversation for results; creates one titled 「创作 · …」 if nil.
    func generate(into conversationID: UUID?) {
        guard canSubmit else {
            if !settings.isAIConfigured {
                errorMessage = "请先在设置中配置 API Key"
            } else if mode == .edit, selectedImageData == nil {
                errorMessage = "请先选择要编辑的图片"
            } else if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "请输入提示词"
            }
            return
        }
        guard let store else {
            errorMessage = "存储未就绪"
            return
        }

        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let modeSnapshot = mode
        let imageData = selectedImageData.map { ImagineService.compressImageData($0) }
        let baseURL = settings.sub2apiBaseURL
        let apiKey = settings.sub2apiAPIKey
        let imgModel = imageModel
        let edModel = editModel
        let vidModel = videoModel

        // Persist preferred models when user generates.
        switch modeSnapshot {
        case .image: settings.preferredImagineImageModel = imgModel
        case .edit: settings.preferredImagineEditModel = edModel
        case .video: settings.preferredImagineVideoModel = vidModel
        }

        isRunning = true
        progressNote = modeSnapshot == .video ? "提交视频任务…" : "生成中…"
        errorMessage = nil
        Haptics.light()

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var trackedConvID: UUID?
            defer {
                self.isRunning = false
                self.progressNote = nil
                self.runTask = nil
                // Always refresh thread after any terminal path (success / fail / timeout / cancel).
                if let id = trackedConvID {
                    self.onConversationUpdated?(id)
                }
            }
            do {
                let convID = try self.ensureConversation(
                    store: store,
                    conversationID: conversationID,
                    prompt: text
                )
                trackedConvID = convID
                let userID = UUID()
                let assistantID = UUID()
                let now = Date()
                let userLabel: String
                switch modeSnapshot {
                case .image: userLabel = "【生图】\(text)"
                case .edit: userLabel = "【编辑】\(text)"
                case .video: userLabel = "【视频】\(text)"
                }

                _ = try store.appendMessage(
                    conversationID: convID,
                    role: .user,
                    content: userLabel,
                    id: userID,
                    createdAt: now
                )

                switch modeSnapshot {
                case .image:
                    try await self.runImage(
                        store: store,
                        conversationID: convID,
                        assistantID: assistantID,
                        caption: text,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        model: imgModel,
                        prompt: text,
                        createdAt: now.addingTimeInterval(0.001)
                    )
                case .edit:
                    guard let imageData else {
                        throw NetworkError.message("缺少编辑图源")
                    }
                    try await self.runEdit(
                        store: store,
                        conversationID: convID,
                        assistantID: assistantID,
                        caption: text,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        model: edModel,
                        prompt: text,
                        imageData: imageData,
                        createdAt: now.addingTimeInterval(0.001)
                    )
                case .video:
                    try await self.runVideo(
                        store: store,
                        conversationID: convID,
                        assistantID: assistantID,
                        caption: text,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        model: vidModel,
                        prompt: text,
                        createdAt: now.addingTimeInterval(0.001)
                    )
                }

                self.prompt = ""
                if modeSnapshot == .edit { self.selectedImageData = nil }
                Haptics.success()
            } catch is CancellationError {
                // Terminal caption written inside runVideo when applicable.
                self.progressNote = "已取消"
            } catch {
                self.errorMessage = ChatViewModel.chineseError(error)
                Haptics.error()
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        // Do not nil `runTask` before cancellation handlers finish marking the message;
        // the task's defer clears state and refreshes the conversation.
        isRunning = false
        progressNote = "已取消"
    }

    // MARK: Private runs

    private func ensureConversation(
        store: ConversationStore,
        conversationID: UUID?,
        prompt: String
    ) throws -> UUID {
        if let conversationID, try store.conversation(id: conversationID) != nil {
            return conversationID
        }
        let flat = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = flat.isEmpty ? "" : String(flat.prefix(ChatLimits.titlePrefixLength))
        let title = suffix.isEmpty ? "创作" : "创作 · \(suffix)"
        let entity = try store.create(title: title, model: settings.preferredModel)
        return entity.id
    }

    private func runImage(
        store: ConversationStore,
        conversationID: UUID,
        assistantID: UUID,
        caption: String,
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        createdAt: Date
    ) async throws {
        progressNote = "正在生成图片…"
        let assets = try await service.generateImage(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            prompt: prompt
        )
        guard let first = assets.first else {
            throw NetworkError.message("生图响应中没有图片")
        }
        progressNote = "保存到本地…"
        let cached = try await service.materializeToCache(first, preferredExtension: "png")
        _ = try store.appendMessage(
            conversationID: conversationID,
            role: .assistant,
            content: caption,
            id: assistantID,
            createdAt: createdAt,
            mediaType: MediaKind.image.rawValue,
            imagePath: cached.relativePath,
            mediaRemoteURL: cached.remoteURL
        )
    }

    private func runEdit(
        store: ConversationStore,
        conversationID: UUID,
        assistantID: UUID,
        caption: String,
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        imageData: Data,
        createdAt: Date
    ) async throws {
        progressNote = "正在编辑图片…"
        let assets = try await service.editImage(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
            imageData: imageData
        )
        guard let first = assets.first else {
            throw NetworkError.message("编辑响应中没有图片")
        }
        progressNote = "保存到本地…"
        let cached = try await service.materializeToCache(first, preferredExtension: "png")
        _ = try store.appendMessage(
            conversationID: conversationID,
            role: .assistant,
            content: caption,
            id: assistantID,
            createdAt: createdAt,
            mediaType: MediaKind.image.rawValue,
            imagePath: cached.relativePath,
            mediaRemoteURL: cached.remoteURL
        )
    }

    private func runVideo(
        store: ConversationStore,
        conversationID: UUID,
        assistantID: UUID,
        caption: String,
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        createdAt: Date
    ) async throws {
        progressNote = "提交视频任务…"
        let requestID = try await service.generateVideo(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            prompt: prompt
        )
        _ = try store.appendMessage(
            conversationID: conversationID,
            role: .assistant,
            content: "视频生成中…",
            id: assistantID,
            createdAt: createdAt,
            mediaType: MediaKind.video.rawValue,
            mediaRequestID: requestID
        )
        // Mid-flight refresh so the thread shows the pending bubble immediately.
        onConversationUpdated?(conversationID)

        progressNote = "等待视频完成…"
        do {
            let status = try await service.pollVideoUntilDone(
                baseURL: baseURL,
                apiKey: apiKey,
                requestID: requestID
            ) { [weak self] status in
                await MainActor.run {
                    switch status {
                    case .pending:
                        self?.progressNote = "视频排队中…"
                    case .processing:
                        self?.progressNote = "视频生成中…"
                    case .completed:
                        self?.progressNote = "下载视频…"
                    case .failed(let message):
                        self?.progressNote = message
                    case .timedOut:
                        self?.progressNote = "视频生成超时…"
                    }
                }
            }

            switch status {
            case .completed(let url, let data):
                progressNote = "保存视频…"
                do {
                    var asset = ImagineAsset(remoteURL: url, data: data, fileExtension: "mp4")
                    if asset.data == nil, let url, !url.isEmpty {
                        asset.data = try await service.downloadData(from: url)
                    }
                    let cached = try await service.materializeToCache(asset, preferredExtension: "mp4")
                    try store.updateMessageMedia(
                        messageID: assistantID,
                        content: caption,
                        mediaType: MediaKind.video.rawValue,
                        videoPath: cached.relativePath,
                        mediaRemoteURL: cached.remoteURL ?? url,
                        mediaRequestID: requestID
                    )
                } catch {
                    // Download / cache failed after upstream completed — still terminal, keep request_id.
                    try markVideoTerminal(
                        store: store,
                        messageID: assistantID,
                        content: "视频失败：\(ChatViewModel.chineseError(error))",
                        requestID: requestID
                    )
                    throw error
                }

            case .failed(let message):
                try markVideoTerminal(
                    store: store,
                    messageID: assistantID,
                    content: "视频失败：\(message)",
                    requestID: requestID
                )
                throw NetworkError.message(message)

            case .timedOut:
                try markVideoTerminal(
                    store: store,
                    messageID: assistantID,
                    content: "视频生成超时，可稍后重试",
                    requestID: requestID
                )
                throw NetworkError.message("视频生成超时，请稍后重试")

            case .pending, .processing:
                // Defensive: poll is expected to only return terminal statuses.
                try markVideoTerminal(
                    store: store,
                    messageID: assistantID,
                    content: "视频生成超时，可稍后重试",
                    requestID: requestID
                )
                throw NetworkError.message("视频生成超时，请稍后重试")
            }
        } catch is CancellationError {
            try markVideoTerminal(
                store: store,
                messageID: assistantID,
                content: "视频已取消",
                requestID: requestID
            )
            throw CancellationError()
        } catch {
            // Transport / parse errors mid-poll: ensure row is not left pending.
            if isVideoMessageStillPending(store: store, messageID: assistantID) {
                try? markVideoTerminal(
                    store: store,
                    messageID: assistantID,
                    content: "视频失败：\(ChatViewModel.chineseError(error))",
                    requestID: requestID
                )
            }
            throw error
        }
    }

    /// Persist a terminal video caption while retaining `mediaRequestID` for retry.
    private func markVideoTerminal(
        store: ConversationStore,
        messageID: UUID,
        content: String,
        requestID: String
    ) throws {
        try store.updateMessageMedia(
            messageID: messageID,
            content: content,
            mediaType: MediaKind.video.rawValue,
            mediaRequestID: requestID
        )
    }

    /// True when the assistant row still looks in-progress (needs a terminal caption).
    private func isVideoMessageStillPending(store: ConversationStore, messageID: UUID) -> Bool {
        guard let message = try? store.message(id: messageID) else { return false }
        if !(message.videoPath ?? "").isEmpty { return false }
        if !(message.mediaRemoteURL ?? "").isEmpty { return false }
        if ChatMessage.isTerminalFailureContent(message.content) { return false }
        return ChatMessage.isVideoInProgressContent(message.content)
    }
}
