import Foundation

/// Caps for chat API history construction (DESIGN.md Chat 实现契约).
enum ChatLimits {
    /// Max user/assistant turns sent to the API (system prompt excluded).
    static let maxHistoryMessages = 40
    /// Per-message content cap (~12k chars, non-tokenizer).
    static let maxMessageCharacters = 12_000
    /// Conversation title: first N characters of first user message.
    static let titlePrefixLength = 24
}

/// Media attachment kind on messages.
enum MediaKind: String, Codable, Hashable {
    case image
    case video
}

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case system, user, assistant }
    let id: UUID
    var role: Role
    var content: String
    var createdAt: Date
    var isStreaming: Bool
    /// nil | image | video
    var mediaKind: MediaKind?
    /// Relative path under Application Support (`Imagine/...`) for still images.
    var imagePath: String?
    /// Relative path under Application Support (`Imagine/...`) for video files.
    var videoPath: String?
    /// Upstream media URL when available.
    var mediaRemoteURL: String?
    /// Video generation request id while polling / for retry.
    var mediaRequestID: String?
    /// Video job still running (runtime; not always persisted separately).
    var isMediaPending: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = .now,
        isStreaming: Bool = false,
        mediaKind: MediaKind? = nil,
        imagePath: String? = nil,
        videoPath: String? = nil,
        mediaRemoteURL: String? = nil,
        mediaRequestID: String? = nil,
        isMediaPending: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.mediaKind = mediaKind
        self.imagePath = imagePath
        self.videoPath = videoPath
        self.mediaRemoteURL = mediaRemoteURL
        self.mediaRequestID = mediaRequestID
        self.isMediaPending = isMediaPending
    }

    var hasMedia: Bool {
        mediaKind != nil
            || imagePath != nil
            || videoPath != nil
            || mediaRemoteURL != nil
            || mediaRequestID != nil
    }

    /// Terminal non-success media caption (failure / timeout / cancel).
    /// Keeps `mediaRequestID` for retry while UI must **not** show a spinner.
    var isMediaFailed: Bool {
        Self.isTerminalFailureContent(content)
    }

    /// Captions written while a video job is still running.
    static func isVideoInProgressContent(_ content: String) -> Bool {
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isEmpty { return true }
        if c.hasPrefix("视频生成中") { return true }
        if c.hasPrefix("视频排队中") { return true }
        if c.hasPrefix("媒体生成中") { return true }
        return false
    }

    /// Failure / timeout / cancel captions (request_id may still be present for retry).
    static func isTerminalFailureContent(_ content: String) -> Bool {
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasPrefix("视频失败") { return true }
        if c.hasPrefix("视频生成超时") { return true }
        if c.contains("生成超时") { return true }
        if c.hasPrefix("视频已取消") { return true }
        return false
    }
}

struct ChatConversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var updatedAt: Date
    var model: String

    init(id: UUID = UUID(), title: String = "新对话", messages: [ChatMessage] = [], updatedAt: Date = .now, model: String = AppSettings.defaultTextModel) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
        self.model = model
    }
}

// OpenAI-compatible request bodies
struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double?

    init(model: String, messages: [ChatMessage], stream: Bool, temperature: Double? = 0.7) {
        self.model = model
        self.messages = messages.map { .init(role: $0.role.rawValue, content: $0.content) }
        self.stream = stream
        self.temperature = temperature
    }
}

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message?
    }
    let choices: [Choice]?
    let error: APIErrorBody?
}

struct APIErrorBody: Decodable {
    let message: String?
    let code: String?
    let type: String?
}

struct ModelsListResponse: Decodable {
    struct Model: Decodable, Identifiable {
        let id: String
        var modelID: String { id }
    }
    let data: [Model]?
}
