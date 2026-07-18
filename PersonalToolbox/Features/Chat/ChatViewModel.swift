import Foundation
import SwiftData
import Combine
import UIKit

/// Chat list + thread state machine: idle ⇄ streaming (stop keeps partial).
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var active: ChatConversation?
    @Published var input: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var availableModels: [String] = AppSettings.defaultModels
    @Published var showModelPicker = false

    private var store: ConversationStore?
    private var settings: AppSettings
    private let service = Sub2APIService.shared
    private var streamTask: Task<Void, Never>?
    /// Monotonic generation for the live stream Task. Stale finish/delta must not clear a newer send.
    private var streamEpoch: UInt = 0
    private var didAttach = false

    init(store: ConversationStore? = nil, settings: AppSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    /// Bind SwiftData context from the view environment (idempotent).
    func attach(modelContext: ModelContext, settings: AppSettings = .shared) {
        self.settings = settings
        if !didAttach || store == nil {
            store = ConversationStore(modelContext: modelContext)
            didAttach = true
        }
    }

    var isConfigured: Bool { settings.isAIConfigured }

    // MARK: - Load / list

    func reload() {
        guard let store else { return }
        do {
            conversations = try store.list().map { $0.toChatConversation() }
            if let activeID = active?.id,
               let refreshed = conversations.first(where: { $0.id == activeID }) {
                // Preserve in-memory streaming flags for the open thread.
                let streamingFlags = Dictionary(
                    uniqueKeysWithValues: (active?.messages ?? []).map { ($0.id, $0.isStreaming) }
                )
                var merged = refreshed
                for i in merged.messages.indices {
                    if streamingFlags[merged.messages[i].id] == true {
                        merged.messages[i].isStreaming = true
                    }
                }
                active = merged
            }
        } catch {
            errorMessage = Self.chineseError(error)
        }
    }

    func loadConversation(id: UUID) {
        guard let store else { return }
        do {
            guard let entity = try store.conversation(id: id) else {
                errorMessage = "会话不存在"
                return
            }
            var conv = entity.toChatConversation()
            // Preserve streaming state if same conversation is already active.
            if let current = active, current.id == id {
                let streaming = Dictionary(
                    uniqueKeysWithValues: current.messages.map { ($0.id, $0.isStreaming) }
                )
                let contents = Dictionary(
                    uniqueKeysWithValues: current.messages.map { ($0.id, $0.content) }
                )
                for i in conv.messages.indices {
                    let mid = conv.messages[i].id
                    if streaming[mid] == true {
                        conv.messages[i].isStreaming = true
                        if let live = contents[mid], live.count > conv.messages[i].content.count {
                            conv.messages[i].content = live
                        }
                    }
                }
            }
            active = conv
            errorMessage = nil
        } catch {
            errorMessage = Self.chineseError(error)
        }
    }

    // MARK: - CRUD

    @discardableResult
    func newConversation() -> ChatConversation? {
        guard let store else { return nil }
        do {
            let entity = try store.create(title: "新对话", model: resolvedTextModel())
            let conv = entity.toChatConversation()
            conversations.insert(conv, at: 0)
            active = conv
            input = ""
            errorMessage = nil
            return conv
        } catch {
            errorMessage = Self.chineseError(error)
            return nil
        }
    }

    /// Preferred model if it is a text model; otherwise default text model (never imagine*).
    private func resolvedTextModel() -> String {
        let preferred = settings.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty, Sub2APIService.isTextModel(preferred) {
            return preferred
        }
        return AppSettings.defaultTextModel
    }

    func deleteConversation(id: UUID) {
        guard let store else { return }
        if isStreaming, active?.id == id {
            stop()
        }
        do {
            try store.delete(conversationID: id)
            conversations.removeAll { $0.id == id }
            if active?.id == id {
                active = nil
            }
        } catch {
            errorMessage = Self.chineseError(error)
        }
    }

    func renameConversation(id: UUID, title: String) {
        guard let store else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.updateTitle(conversationID: id, title: trimmed)
            if let idx = conversations.firstIndex(where: { $0.id == id }) {
                conversations[idx].title = trimmed
            }
            if active?.id == id {
                active?.title = trimmed
            }
        } catch {
            errorMessage = Self.chineseError(error)
        }
    }

    func selectModel(_ model: String) {
        guard Sub2APIService.isTextModel(model) else { return }
        guard let store, var conv = active else {
            settings.preferredModel = model
            return
        }
        do {
            try store.updateModel(conversationID: conv.id, model: model)
            conv.model = model
            active = conv
            if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
                conversations[idx].model = model
            }
            settings.preferredModel = model
        } catch {
            errorMessage = Self.chineseError(error)
        }
    }

    // MARK: - Models picker data

    func loadModels() async {
        guard isConfigured else {
            availableModels = AppSettings.defaultModels
            return
        }
        do {
            let remote = try await service.listModels(
                baseURL: settings.sub2apiBaseURL,
                apiKey: settings.sub2apiAPIKey
            )
            let textOnly = remote.filter { Sub2APIService.isTextModel($0) }
            var set = Set(AppSettings.defaultModels)
            textOnly.forEach { set.insert($0) }
            if let current = active?.model, Sub2APIService.isTextModel(current) {
                set.insert(current)
            }
            let preferred = settings.preferredModel
            if Sub2APIService.isTextModel(preferred), !preferred.isEmpty {
                set.insert(preferred)
            }
            availableModels = set.sorted()
        } catch {
            if availableModels.isEmpty {
                availableModels = AppSettings.defaultModels
            }
        }
    }

    // MARK: - Send / stream / stop

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard let store else { return }

        guard isConfigured else {
            errorMessage = "请先在设置中配置 API Key"
            return
        }

        if active == nil {
            guard newConversation() != nil else { return }
        }
        guard var conv = active else { return }

        let userID = UUID()
        let assistantID = UUID()
        let now = Date()

        do {
            _ = try store.appendMessage(
                conversationID: conv.id,
                role: .user,
                content: text,
                id: userID,
                createdAt: now
            )
            _ = try store.appendMessage(
                conversationID: conv.id,
                role: .assistant,
                content: "",
                id: assistantID,
                createdAt: now.addingTimeInterval(0.001)
            )
            if let entity = try store.conversation(id: conv.id) {
                conv = entity.toChatConversation()
                if let idx = conv.messages.firstIndex(where: { $0.id == assistantID }) {
                    conv.messages[idx].isStreaming = true
                }
            }
        } catch {
            errorMessage = Self.chineseError(error)
            return
        }

        input = ""
        active = conv
        upsertConversationInList(conv)
        errorMessage = nil
        streamEpoch &+= 1
        let epoch = streamEpoch
        isStreaming = true
        Haptics.light()

        let apiMessages = Self.buildAPIMessages(
            from: conv,
            systemPrompt: settings.systemPrompt
        )
        // Clamp to text models even if conversation.model was corrupted/legacy.
        let model = Sub2APIService.isTextModel(conv.model) ? conv.model : resolvedTextModel()
        if model != conv.model {
            try? store.updateModel(conversationID: conv.id, model: model)
            conv.model = model
            active = conv
            upsertConversationInList(conv)
        }
        let baseURL = settings.sub2apiBaseURL
        let apiKey = settings.sub2apiAPIKey
        let conversationID = conv.id

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var assembled = ""
            do {
                let stream = await self.service.streamChat(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    messages: apiMessages
                )
                for try await delta in stream {
                    if Task.isCancelled { break }
                    assembled += delta
                    self.applyAssistantDelta(
                        conversationID: conversationID,
                        messageID: assistantID,
                        content: assembled,
                        isStreaming: true,
                        epoch: epoch
                    )
                }

                self.finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: assembled,
                    error: nil,
                    cancelled: Task.isCancelled,
                    epoch: epoch
                )
            } catch is CancellationError {
                self.finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: assembled,
                    error: nil,
                    cancelled: true,
                    epoch: epoch
                )
            } catch {
                self.finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: assembled,
                    error: error,
                    cancelled: false,
                    epoch: epoch
                )
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        // Move UI to idle immediately (DESIGN interruptibility).
        // Bump epoch so a late finishStream from the cancelled task cannot nil a future streamTask
        // or force isStreaming=false after a quick re-send (Issue 6). Store finalization still runs
        // for the cancelled messageID when that task reaches finishStream.
        if isStreaming {
            streamEpoch &+= 1
            isStreaming = false
            streamTask = nil
            if var conv = active,
               let idx = conv.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                conv.messages[idx].isStreaming = false
                let content = conv.messages[idx].content
                try? store?.updateMessageContent(messageID: conv.messages[idx].id, content: content)
                active = conv
                upsertConversationInList(conv)
            }
        }
    }

    func copyMessage(_ message: ChatMessage) {
        UIPasteboard.general.string = message.content
        Haptics.success()
    }

    // MARK: - History window (契约)

    /// Builds API payload: optional system + last N non-streaming user/assistant turns.
    /// Media-only assistant rows are kept as short captions so the text model has light context.
    static func buildAPIMessages(from conversation: ChatConversation, systemPrompt: String) -> [ChatMessage] {
        var history = conversation.messages.filter { msg in
            !msg.isStreaming
                && !msg.isMediaPending
                && (msg.role == .user || msg.role == .assistant)
        }
        if let last = history.last, last.role == .assistant, last.content.isEmpty {
            history.removeLast()
        }
        if history.count > ChatLimits.maxHistoryMessages {
            history = Array(history.suffix(ChatLimits.maxHistoryMessages))
        }
        history = history.map { msg in
            var copy = msg
            if copy.content.count > ChatLimits.maxMessageCharacters {
                copy.content = String(copy.content.suffix(ChatLimits.maxMessageCharacters))
            }
            return copy
        }

        var result: [ChatMessage] = []
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            result.append(ChatMessage(role: .system, content: prompt))
        }
        result.append(contentsOf: history)
        return result
    }

    // MARK: - Private helpers

    /// Persist delta always by messageID; live-epoch only may mark `isStreaming` true on UI.
    private func applyAssistantDelta(
        conversationID: UUID,
        messageID: UUID,
        content: String,
        isStreaming streamingFlag: Bool,
        epoch: UInt
    ) {
        try? store?.updateMessageContent(messageID: messageID, content: content)

        if var conv = active, conv.id == conversationID {
            if let idx = conv.messages.firstIndex(where: { $0.id == messageID }) {
                conv.messages[idx].content = content
                // Stale epochs must not re-light a stopped bubble or fight a newer stream.
                conv.messages[idx].isStreaming = (epoch == streamEpoch) && streamingFlag
            }
            conv.updatedAt = .now
            active = conv
            upsertConversationInList(conv)
        } else if epoch == streamEpoch, let idx = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[idx].updatedAt = .now
            conversations.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    /// Conversation-ID-scoped finalization: always writes/deletes via store by messageID.
    /// Clears `isStreaming` / `streamTask` only when this call owns the current `streamEpoch`.
    private func finishStream(
        conversationID: UUID,
        messageID: UUID,
        content: String,
        error: Error?,
        cancelled: Bool,
        epoch: UInt
    ) {
        let ownsEpoch = (epoch == streamEpoch)
        defer {
            if ownsEpoch {
                isStreaming = false
                streamTask = nil
            }
        }

        let emptyOnError = content.isEmpty && error != nil && !cancelled

        // Always finalize this message in the store (even if a newer epoch is live).
        if emptyOnError {
            try? store?.deleteMessage(messageID: messageID)
            if ownsEpoch {
                if let error {
                    errorMessage = Self.chineseError(error)
                }
                Haptics.error()
            }
        } else {
            try? store?.updateMessageContent(messageID: messageID, content: content)
            if ownsEpoch {
                if let error, !cancelled {
                    errorMessage = Self.chineseError(error)
                    Haptics.error()
                } else if !cancelled {
                    Haptics.success()
                }
            }
        }

        // Refresh title / updatedAt from store for list row.
        var listConv: ChatConversation?
        if let entity = try? store?.conversation(id: conversationID) {
            listConv = entity.toChatConversation()
        }

        if var conv = active, conv.id == conversationID {
            if emptyOnError {
                conv.messages.removeAll { $0.id == messageID }
            } else if let idx = conv.messages.firstIndex(where: { $0.id == messageID }) {
                conv.messages[idx].content = content
                conv.messages[idx].isStreaming = false
            }
            if let entity = try? store?.conversation(id: conversationID) {
                conv.title = entity.title
                conv.updatedAt = entity.updatedAt
            } else {
                conv.updatedAt = .now
            }
            active = conv
            upsertConversationInList(conv)
        } else if var refreshed = listConv {
            // Only force all streaming flags off for live-epoch snapshots; stale finish
            // must not clear a newer stream's bubble flags when reloading from store.
            if ownsEpoch {
                for i in refreshed.messages.indices {
                    refreshed.messages[i].isStreaming = false
                }
            }
            if emptyOnError {
                refreshed.messages.removeAll { $0.id == messageID }
            }
            upsertConversationInList(refreshed)
        } else if ownsEpoch {
            reload()
        }
    }

    private func upsertConversationInList(_ conv: ChatConversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx] = conv
            conversations.sort { $0.updatedAt > $1.updatedAt }
        } else {
            conversations.insert(conv, at: 0)
        }
    }

    static func chineseError(_ error: Error) -> String {
        if let net = error as? NetworkError {
            return net.errorDescription ?? "网络错误"
        }
        if let storeErr = error as? ConversationStore.StoreError {
            return storeErr.errorDescription ?? "存储错误"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "无网络连接"
            case NSURLErrorTimedOut: return "请求超时"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "无法连接服务器"
            case NSURLErrorSecureConnectionFailed: return "安全连接失败"
            case NSURLErrorCancelled: return "已取消"
            default: break
            }
        }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "未知错误" : text
    }
}
