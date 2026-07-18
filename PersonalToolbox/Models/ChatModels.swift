import Foundation

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case system, user, assistant }
    let id: UUID
    var role: Role
    var content: String
    var createdAt: Date
    var isStreaming: Bool

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = .now, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
    }
}

struct ChatConversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var updatedAt: Date
    var model: String

    init(id: UUID = UUID(), title: String = "新对话", messages: [ChatMessage] = [], updatedAt: Date = .now, model: String = "grok-4.5") {
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
