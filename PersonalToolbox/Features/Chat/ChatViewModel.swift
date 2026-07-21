import Foundation
import SwiftData
import Combine
import UIKit

/// Chat list + thread state machine.
/// Supports **multiple concurrent conversation streams** (one active stream per conversation).
/// Background: silent-audio keep-alive + BG task + non-stream completion so replies finish off-screen.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversations: [ChatConversation] = []
    @Published var active: ChatConversation?
    @Published var input: String = ""
    /// True when the **currently open** conversation is streaming (composer / stop button).
    @Published private(set) var isStreaming: Bool = false
    /// Conversation IDs with an in-flight stream (list badges / multi-chat).
    @Published private(set) var streamingConversationIDs: Set<UUID> = []
    @Published var errorMessage: String?
    @Published var availableModels: [String] = AppSettings.defaultModels
    @Published var showModelPicker = false

    private var store: ConversationStore?
    private var settings: AppSettings
    private let service = Sub2APIService.shared
    private var didAttach = false

    /// Per-conversation live stream bookkeeping (includes recovery payload for background completion).
    private struct LiveStream {
        let task: Task<Void, Never>
        let epoch: UInt
        let assistantMessageID: UUID
        let baseURL: String
        let apiKey: String
        let model: String
        let apiMessages: [ChatMessage]
    }

    private var liveStreams: [UUID: LiveStream] = [:]
    /// Monotonic epoch per conversation — stale finish/delta must not clear a newer send on that thread.
    private var streamEpochs: [UUID: UInt] = [:]
    /// Shared background task (supplementary to audio keep-alive).
    private var sharedBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// Extra keep-alive retain taken on `didEnterBackground` (balanced on foreground / idle).
    private var backgroundExtraRetain = false

    init(store: ConversationStore? = nil, settings: AppSettings = .shared) {
        self.store = store
        self.settings = settings
        installLifecycleObservers()
    }

    deinit {
        // Observers removed on main if still registered — best-effort.
        for token in lifecycleObservers {
            NotificationCenter.default.removeObserver(token)
        }
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

    func isConversationStreaming(_ id: UUID) -> Bool {
        streamingConversationIDs.contains(id)
    }

    // MARK: - Load / list

    func reload() {
        guard let store else { return }
        do {
            conversations = try store.list().map { $0.toChatConversation() }
            if let activeID = active?.id,
               let refreshed = conversations.first(where: { $0.id == activeID }) {
                active = mergeLiveStreamingState(into: refreshed)
            }
            // Re-apply streaming flags on list rows that are still live.
            for id in streamingConversationIDs {
                if let idx = conversations.firstIndex(where: { $0.id == id }) {
                    conversations[idx] = mergeLiveStreamingState(into: conversations[idx])
                }
            }
            refreshIsStreamingFlag()
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
            // Preserve in-memory content for the same open thread (latest tokens may be ahead of store flush timing).
            if let current = active, current.id == id {
                let contents = Dictionary(
                    uniqueKeysWithValues: current.messages.map { ($0.id, $0.content) }
                )
                for i in conv.messages.indices {
                    let mid = conv.messages[i].id
                    if let live = contents[mid], live.count > conv.messages[i].content.count {
                        conv.messages[i].content = live
                    }
                }
            }
            active = mergeLiveStreamingState(into: conv)
            // Only clear banner when switching into a healthy thread (keep error if it belongs to this id).
            if !streamingConversationIDs.contains(id) {
                // Keep error if it was for this conversation; otherwise clear stale banner from another thread.
                // We don't track error-per-conversation today — clear on navigate for cleaner UX.
                errorMessage = nil
            }
            refreshIsStreamingFlag()
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
            refreshIsStreamingFlag()
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
        if streamingConversationIDs.contains(id) {
            stop(conversationID: id)
        }
        do {
            try store.delete(conversationID: id)
            conversations.removeAll { $0.id == id }
            if active?.id == id {
                active = nil
            }
            refreshIsStreamingFlag()
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
        guard !text.isEmpty else { return }
        guard let store else { return }

        guard isConfigured else {
            errorMessage = "请先在设置中配置 API Key"
            return
        }

        if active == nil {
            guard newConversation() != nil else { return }
        }
        guard var conv = active else { return }

        // Only block a second send on the **same** conversation; other chats may stream in parallel.
        if streamingConversationIDs.contains(conv.id) {
            return
        }

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

        let epoch = nextEpoch(for: conv.id)
        markStreaming(conversationID: conv.id, on: true)
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

        // Hold process in background for the whole stream lifetime.
        ChatStreamKeepAlive.shared.retain()
        beginSharedBackgroundTaskIfNeeded()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runStreamLoop(
                conversationID: conversationID,
                assistantID: assistantID,
                epoch: epoch,
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                apiMessages: apiMessages
            )
        }

        liveStreams[conversationID] = LiveStream(
            task: task,
            epoch: epoch,
            assistantMessageID: assistantID,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            apiMessages: apiMessages
        )
        refreshIsStreamingFlag()
    }

    /// SSE first; on lifecycle interrupt, finish with non-stream so background replies complete.
    private func runStreamLoop(
        conversationID: UUID,
        assistantID: UUID,
        epoch: UInt,
        baseURL: String,
        apiKey: String,
        model: String,
        apiMessages: [ChatMessage]
    ) async {
        var assembled = ""
        do {
            let stream = await service.streamChat(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                messages: apiMessages
            )
            for try await delta in stream {
                if Task.isCancelled { break }
                assembled += delta
                applyAssistantDelta(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: assembled,
                    isStreaming: true,
                    epoch: epoch
                )
            }

            if Task.isCancelled {
                // User stop / explicit cancel — keep partial, no error.
                finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: assembled,
                    error: nil,
                    cancelled: true,
                    softInterrupt: false,
                    epoch: epoch
                )
            } else {
                finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: assembled,
                    error: nil,
                    cancelled: false,
                    softInterrupt: false,
                    epoch: epoch
                )
            }
        } catch is CancellationError {
            finishStream(
                conversationID: conversationID,
                messageID: assistantID,
                content: assembled,
                error: nil,
                cancelled: true,
                softInterrupt: false,
                epoch: epoch
            )
        } catch {
            if Task.isCancelled {
                finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: assembled,
                    error: nil,
                    cancelled: true,
                    softInterrupt: false,
                    epoch: epoch
                )
                return
            }

            // Network / suspend flap: complete the full reply via non-stream while keep-alive holds us.
            if Self.isLifecycleInterrupt(error) {
                await completeViaNonStream(
                    conversationID: conversationID,
                    assistantID: assistantID,
                    epoch: epoch,
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    apiMessages: apiMessages,
                    partial: assembled
                )
                return
            }

            finishStream(
                conversationID: conversationID,
                messageID: assistantID,
                content: assembled,
                error: error,
                cancelled: false,
                softInterrupt: false,
                epoch: epoch
            )
        }
    }

    /// Prefer a full non-stream answer over a truncated SSE partial when the stream is interrupted.
    private func completeViaNonStream(
        conversationID: UUID,
        assistantID: UUID,
        epoch: UInt,
        baseURL: String,
        apiKey: String,
        model: String,
        apiMessages: [ChatMessage],
        partial: String
    ) async {
        // Renew background execution window for the long non-stream call.
        beginSharedBackgroundTaskIfNeeded()
        do {
            let text = try await service.nonStreamChat(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                messages: apiMessages
            )
            if Task.isCancelled {
                finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: text.isEmpty ? partial : text,
                    error: nil,
                    cancelled: true,
                    softInterrupt: false,
                    epoch: epoch
                )
            } else {
                finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: text.isEmpty ? partial : text,
                    error: nil,
                    cancelled: false,
                    softInterrupt: false,
                    epoch: epoch
                )
            }
        } catch is CancellationError {
            finishStream(
                conversationID: conversationID,
                messageID: assistantID,
                content: partial,
                error: nil,
                cancelled: true,
                softInterrupt: false,
                epoch: epoch
            )
        } catch {
            if !partial.isEmpty {
                // Keep what we have rather than empty error bubble.
                finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: partial,
                    error: nil,
                    cancelled: false,
                    softInterrupt: true,
                    epoch: epoch
                )
            } else {
                finishStream(
                    conversationID: conversationID,
                    messageID: assistantID,
                    content: partial,
                    error: error,
                    cancelled: false,
                    softInterrupt: false,
                    epoch: epoch
                )
            }
        }
    }

    /// Stop the open conversation's stream (or a specific conversation).
    func stop(conversationID: UUID? = nil) {
        let id = conversationID ?? active?.id
        guard let id else { return }
        guard let handle = liveStreams[id] else {
            // No live task but UI may still show streaming flag — clear it.
            markStreaming(conversationID: id, on: false)
            if var conv = active, conv.id == id {
                clearStreamingFlags(on: &conv)
                active = conv
                upsertConversationInList(conv)
            }
            refreshIsStreamingFlag()
            return
        }

        // Invalidate epoch so a late finish cannot re-enter streaming UI for this id.
        streamEpochs[id] = (streamEpochs[id] ?? handle.epoch) &+ 1
        handle.task.cancel()
        liveStreams.removeValue(forKey: id)
        markStreaming(conversationID: id, on: false)
        // Balance the retain() taken when this stream started.
        ChatStreamKeepAlive.shared.release()

        // Snapshot partial content into store + UI immediately (interruptibility).
        if var conv = (active?.id == id ? active : conversations.first(where: { $0.id == id })) {
            if let idx = conv.messages.firstIndex(where: { $0.id == handle.assistantMessageID }) {
                conv.messages[idx].isStreaming = false
                let content = conv.messages[idx].content
                try? store?.updateMessageContent(messageID: handle.assistantMessageID, content: content)
            } else if let idx = conv.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                conv.messages[idx].isStreaming = false
                try? store?.updateMessageContent(messageID: conv.messages[idx].id, content: conv.messages[idx].content)
            }
            if active?.id == id {
                active = conv
            }
            upsertConversationInList(conv)
        }

        endSharedBackgroundTaskIfIdle()
        refreshIsStreamingFlag()
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

    private func nextEpoch(for conversationID: UUID) -> UInt {
        let next = (streamEpochs[conversationID] ?? 0) &+ 1
        streamEpochs[conversationID] = next
        return next
    }

    private func ownsEpoch(_ epoch: UInt, conversationID: UUID) -> Bool {
        streamEpochs[conversationID] == epoch
    }

    private func markStreaming(conversationID: UUID, on: Bool) {
        if on {
            streamingConversationIDs.insert(conversationID)
        } else {
            streamingConversationIDs.remove(conversationID)
        }
        refreshIsStreamingFlag()
    }

    private func refreshIsStreamingFlag() {
        let next = active.map { streamingConversationIDs.contains($0.id) } ?? false
        if isStreaming != next {
            isStreaming = next
        }
    }

    private func mergeLiveStreamingState(into conv: ChatConversation) -> ChatConversation {
        guard let handle = liveStreams[conv.id] else {
            var cleared = conv
            clearStreamingFlags(on: &cleared)
            return cleared
        }
        var merged = conv
        if let idx = merged.messages.firstIndex(where: { $0.id == handle.assistantMessageID }) {
            merged.messages[idx].isStreaming = true
        }
        return merged
    }

    private func clearStreamingFlags(on conv: inout ChatConversation) {
        for i in conv.messages.indices {
            conv.messages[i].isStreaming = false
        }
    }

    /// Persist delta always by messageID; only live-epoch may mark `isStreaming` true on UI.
    private func applyAssistantDelta(
        conversationID: UUID,
        messageID: UUID,
        content: String,
        isStreaming streamingFlag: Bool,
        epoch: UInt
    ) {
        try? store?.updateMessageContent(messageID: messageID, content: content)

        let live = ownsEpoch(epoch, conversationID: conversationID) && streamingFlag

        if var conv = active, conv.id == conversationID {
            if let idx = conv.messages.firstIndex(where: { $0.id == messageID }) {
                conv.messages[idx].content = content
                conv.messages[idx].isStreaming = live
            }
            conv.updatedAt = .now
            active = conv
            upsertConversationInList(conv)
        } else if let idx = conversations.firstIndex(where: { $0.id == conversationID }) {
            // Background conversation: keep list row fresh without hijacking `active`.
            var conv = conversations[idx]
            if let mIdx = conv.messages.firstIndex(where: { $0.id == messageID }) {
                conv.messages[mIdx].content = content
                conv.messages[mIdx].isStreaming = live
            } else if let entity = try? store?.conversation(id: conversationID) {
                conv = entity.toChatConversation()
                if let mIdx = conv.messages.firstIndex(where: { $0.id == messageID }) {
                    conv.messages[mIdx].content = content
                    conv.messages[mIdx].isStreaming = live
                }
            }
            conv.updatedAt = .now
            conversations[idx] = conv
            conversations.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    /// Conversation-ID-scoped finalization: always writes/deletes via store by messageID.
    private func finishStream(
        conversationID: UUID,
        messageID: UUID,
        content: String,
        error: Error?,
        cancelled: Bool,
        softInterrupt: Bool,
        epoch: UInt
    ) {
        let owns = ownsEpoch(epoch, conversationID: conversationID)
        defer {
            if owns {
                if let handle = liveStreams[conversationID], handle.epoch == epoch {
                    liveStreams.removeValue(forKey: conversationID)
                }
                markStreaming(conversationID: conversationID, on: false)
                ChatStreamKeepAlive.shared.release()
                endSharedBackgroundTaskIfIdle()
            }
            refreshIsStreamingFlag()
        }

        let emptyOnError = content.isEmpty && error != nil && !cancelled && !softInterrupt
        let appInBackground = UIApplication.shared.applicationState != .active

        // Always finalize this message in the store (even if a newer epoch is live).
        if emptyOnError {
            try? store?.deleteMessage(messageID: messageID)
            if owns {
                if active?.id == conversationID, let error {
                    errorMessage = Self.chineseError(error)
                    Haptics.error()
                }
                if appInBackground {
                    LocalNotifier.notify(
                        id: "chat.fail.\(conversationID.uuidString)",
                        title: "回复失败",
                        body: Self.chineseError(error ?? NetworkError.message("未知错误"))
                    )
                }
            }
        } else {
            try? store?.updateMessageContent(messageID: messageID, content: content)
            if owns {
                if active?.id == conversationID {
                    if let error, !cancelled, !softInterrupt {
                        errorMessage = Self.chineseError(error)
                        Haptics.error()
                    } else if !cancelled && !softInterrupt {
                        Haptics.success()
                        UIAccessibility.post(notification: .announcement, argument: "回复完成")
                    }
                }
                // Background completion ping so the user knows it finished off-screen.
                if appInBackground, !cancelled, !softInterrupt || !content.isEmpty {
                    let preview = content
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let body: String
                    if preview.isEmpty {
                        body = softInterrupt ? "生成已中断" : "助手已完成回复"
                    } else {
                        body = String(preview.prefix(80))
                    }
                    LocalNotifier.notify(
                        id: "chat.done.\(messageID.uuidString)",
                        title: softInterrupt ? "回复已保存（可能不完整）" : "回复完成",
                        body: body
                    )
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
            if owns {
                for i in refreshed.messages.indices {
                    if refreshed.messages[i].id == messageID {
                        refreshed.messages[i].isStreaming = false
                        if !emptyOnError {
                            refreshed.messages[i].content = content
                        }
                    }
                }
            }
            if emptyOnError {
                refreshed.messages.removeAll { $0.id == messageID }
            }
            upsertConversationInList(refreshed)
        } else if owns {
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

    // MARK: - Background task + lifecycle

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        // `queue: .main` already hops to the main actor — avoid nested Task capturing weak self.
        let bg = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
        let fg = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillEnterForeground()
        }
        lifecycleObservers = [bg, fg]
    }

    private func handleDidEnterBackground() {
        guard !streamingConversationIDs.isEmpty else { return }
        // Extra retain so keep-alive survives brief stream-bookkeeping gaps while suspended.
        if !backgroundExtraRetain {
            ChatStreamKeepAlive.shared.retain()
            backgroundExtraRetain = true
        }
        beginSharedBackgroundTaskIfNeeded()
    }

    private func handleWillEnterForeground() {
        releaseBackgroundExtraRetainIfNeeded()
        // Refresh flags for any streams that finished off-screen.
        reload()
    }

    private func releaseBackgroundExtraRetainIfNeeded() {
        guard backgroundExtraRetain else { return }
        ChatStreamKeepAlive.shared.release()
        backgroundExtraRetain = false
    }

    private func beginSharedBackgroundTaskIfNeeded() {
        // Always renew so long generations get a fresh expiration window when possible.
        if sharedBackgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(sharedBackgroundTaskID)
            sharedBackgroundTaskID = .invalid
        }
        sharedBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ChatStream") { [weak self] in
            Task { @MainActor in
                self?.handleBackgroundTaskExpired()
            }
        }
    }

    private func endSharedBackgroundTaskIfIdle() {
        guard streamingConversationIDs.isEmpty else { return }
        releaseBackgroundExtraRetainIfNeeded()
        guard sharedBackgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(sharedBackgroundTaskID)
        sharedBackgroundTaskID = .invalid
    }

    /// BG task budget ran out. Do **not** kill streams — audio keep-alive holds the process;
    /// try to open another short BG window for non-stream fallback work.
    private func handleBackgroundTaskExpired() {
        if sharedBackgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(sharedBackgroundTaskID)
            sharedBackgroundTaskID = .invalid
        }

        guard !streamingConversationIDs.isEmpty else {
            releaseBackgroundExtraRetainIfNeeded()
            return
        }
        // Re-assert keep-alive session (handles audio interruptions).
        ChatStreamKeepAlive.shared.retain()
        ChatStreamKeepAlive.shared.release()
        beginSharedBackgroundTaskIfNeeded()
    }

    /// Network / lifecycle interruptions that should not scare the user after app switch.
    static func isLifecycleInterrupt(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled,
                 .networkConnectionLost,
                 .timedOut,
                 .notConnectedToInternet,
                 .dataNotAllowed,
                 .internationalRoamingOff,
                 .callIsActive,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .secureConnectionFailed:
                return true
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorSecureConnectionFailed:
                return true
            default:
                break
            }
        }
        // Some stacks wrap cancellation.
        let text = error.localizedDescription.lowercased()
        if text.contains("cancel") || text.contains("timed out") || text.contains("connection lost") {
            return true
        }
        return false
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
            case NSURLErrorNetworkConnectionLost: return "连接中断，请重试"
            default: break
            }
        }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "未知错误" : text
    }
}
