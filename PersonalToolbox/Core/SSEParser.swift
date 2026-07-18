import Foundation

enum SSEParser {
    /// Parse OpenAI-compatible chat completion SSE stream lines into text deltas.
    static func deltas(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return [] }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [] }
        guard let data = payload.data(using: .utf8) else { return [] }

        // Chat Completions stream
        if let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) {
            return chunk.choices.compactMap { $0.delta?.content }.filter { !$0.isEmpty }
        }

        // Responses API stream (partial support)
        if let event = try? JSONDecoder().decode(ResponsesStreamEvent.self, from: data) {
            if let text = event.delta ?? event.text {
                return [text]
            }
        }
        return []
    }
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta?
    }
    let choices: [Choice]
}

private struct ResponsesStreamEvent: Decodable {
    let delta: String?
    let text: String?
}
