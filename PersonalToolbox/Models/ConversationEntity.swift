import Foundation
import SwiftData

/// Persisted chat session. Runtime counterpart: `ChatConversation`.
@Model
final class ConversationEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var model: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
    var messages: [MessageEntity]

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        model: String = AppSettings.defaultTextModel,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [MessageEntity] = []
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

/// Persisted chat message. Runtime counterpart: `ChatMessage` (`isStreaming` is not persisted).
@Model
final class MessageEntity {
    @Attribute(.unique) var id: UUID
    /// `system` | `user` | `assistant`
    var roleRaw: String
    var content: String
    var createdAt: Date

    // MARK: Media placeholders (PR-3c fills these in)
    /// nil | `image` | `video` — alias for user-facing `mediaType`
    var mediaKindRaw: String?
    /// Local sandbox path under Application Support (image or video file)
    var imagePath: String?
    var videoPath: String?
    /// Upstream URL when available
    var mediaRemoteURL: String?
    /// Video generation request id while polling
    var mediaRequestID: String?

    var conversation: ConversationEntity?

    /// Convenience mirror of `mediaKindRaw`.
    var mediaType: String? {
        get { mediaKindRaw }
        set { mediaKindRaw = newValue }
    }

    init(
        id: UUID = UUID(),
        roleRaw: String,
        content: String,
        createdAt: Date = .now,
        mediaKindRaw: String? = nil,
        imagePath: String? = nil,
        videoPath: String? = nil,
        mediaRemoteURL: String? = nil,
        mediaRequestID: String? = nil,
        conversation: ConversationEntity? = nil
    ) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.createdAt = createdAt
        self.mediaKindRaw = mediaKindRaw
        self.imagePath = imagePath
        self.videoPath = videoPath
        self.mediaRemoteURL = mediaRemoteURL
        self.mediaRequestID = mediaRequestID
        self.conversation = conversation
    }

    convenience init(
        id: UUID = UUID(),
        role: ChatMessage.Role,
        content: String,
        createdAt: Date = .now,
        conversation: ConversationEntity? = nil
    ) {
        self.init(
            id: id,
            roleRaw: role.rawValue,
            content: content,
            createdAt: createdAt,
            conversation: conversation
        )
    }
}

// MARK: - Runtime mapping

extension MessageEntity {
    var role: ChatMessage.Role {
        get { ChatMessage.Role(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            createdAt: createdAt,
            isStreaming: false
        )
    }
}

extension ConversationEntity {
    /// Messages sorted oldest → newest for display / API history.
    var sortedMessages: [MessageEntity] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    func toChatConversation() -> ChatConversation {
        ChatConversation(
            id: id,
            title: title,
            messages: sortedMessages.map { $0.toChatMessage() },
            updatedAt: updatedAt,
            model: model
        )
    }
}
