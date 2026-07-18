import Foundation
import SwiftData

/// SwiftData-backed CRUD for chat sessions and messages.
/// All APIs hop to the main actor; call from UI / ViewModels freely.
@MainActor
final class ConversationStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create

    /// Creates an empty conversation and persists it.
    @discardableResult
    func create(
        title: String = "新对话",
        model: String = AppSettings.defaultTextModel
    ) throws -> ConversationEntity {
        let entity = ConversationEntity(title: title, model: model)
        modelContext.insert(entity)
        try modelContext.save()
        return entity
    }

    // MARK: - List / fetch

    /// All conversations, newest `updatedAt` first.
    func list() throws -> [ConversationEntity] {
        let descriptor = FetchDescriptor<ConversationEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func conversation(id: UUID) throws -> ConversationEntity? {
        let descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Update title / model

    func updateTitle(conversationID: UUID, title: String) throws {
        guard let conversation = try conversation(id: conversationID) else {
            throw StoreError.conversationNotFound(conversationID)
        }
        conversation.title = title
        conversation.updatedAt = .now
        try modelContext.save()
    }

    func updateModel(conversationID: UUID, model: String) throws {
        guard let conversation = try conversation(id: conversationID) else {
            throw StoreError.conversationNotFound(conversationID)
        }
        conversation.model = model
        conversation.updatedAt = .now
        try modelContext.save()
    }

    // MARK: - Messages

    /// Appends a message to the conversation and bumps `updatedAt`.
    @discardableResult
    func appendMessage(
        conversationID: UUID,
        role: ChatMessage.Role,
        content: String,
        id: UUID = UUID(),
        createdAt: Date = .now,
        mediaType: String? = nil,
        imagePath: String? = nil,
        videoPath: String? = nil,
        mediaRemoteURL: String? = nil,
        mediaRequestID: String? = nil
    ) throws -> MessageEntity {
        guard let conversation = try conversation(id: conversationID) else {
            throw StoreError.conversationNotFound(conversationID)
        }
        let message = MessageEntity(
            id: id,
            roleRaw: role.rawValue,
            content: content,
            createdAt: createdAt,
            mediaKindRaw: mediaType,
            imagePath: imagePath,
            videoPath: videoPath,
            mediaRemoteURL: mediaRemoteURL,
            mediaRequestID: mediaRequestID,
            conversation: conversation
        )
        modelContext.insert(message)
        conversation.updatedAt = .now

        // Auto-title from first user message (design: first 24 chars, strip newlines).
        if role == .user,
           conversation.title == "新对话" || conversation.title.isEmpty {
            let flattened = content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !flattened.isEmpty {
                conversation.title = String(flattened.prefix(ChatLimits.titlePrefixLength))
            }
        }

        try modelContext.save()
        return message
    }

    /// Updates message content (streaming deltas) and optionally clears streaming state side-effects.
    func updateMessageContent(messageID: UUID, content: String) throws {
        guard let message = try message(id: messageID) else {
            throw StoreError.messageNotFound(messageID)
        }
        message.content = content
        message.conversation?.updatedAt = .now
        try modelContext.save()
    }

    /// Messages for a conversation, oldest → newest.
    func loadMessages(conversationID: UUID) throws -> [MessageEntity] {
        guard let conversation = try conversation(id: conversationID) else {
            throw StoreError.conversationNotFound(conversationID)
        }
        return conversation.sortedMessages
    }

    func message(id: UUID) throws -> MessageEntity? {
        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Delete

    func delete(conversationID: UUID) throws {
        guard let conversation = try conversation(id: conversationID) else {
            throw StoreError.conversationNotFound(conversationID)
        }
        // Cascade deletes messages via relationship deleteRule.
        // PR-3c may also purge Imagine local files here.
        modelContext.delete(conversation)
        try modelContext.save()
    }

    func deleteMessage(messageID: UUID) throws {
        guard let message = try message(id: messageID) else {
            throw StoreError.messageNotFound(messageID)
        }
        let parent = message.conversation
        modelContext.delete(message)
        parent?.updatedAt = .now
        try modelContext.save()
    }

    // MARK: - DEBUG helpers

    #if DEBUG
    /// Wipe all conversations (destructive schema reset helper). iOS 17–safe (no batch delete API).
    func deleteAll() throws {
        for conversation in try list() {
            modelContext.delete(conversation)
        }
        try modelContext.save()
    }
    #endif

    // MARK: - Errors

    enum StoreError: LocalizedError {
        case conversationNotFound(UUID)
        case messageNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .conversationNotFound(let id):
                return "会话不存在：\(id.uuidString)"
            case .messageNotFound(let id):
                return "消息不存在：\(id.uuidString)"
            }
        }
    }
}
