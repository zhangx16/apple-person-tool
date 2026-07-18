import Foundation

actor Sub2APIService {
    static let shared = Sub2APIService()
    private let client = NetworkClient.shared

    private func headers(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
            "Accept": "text/event-stream, application/json"
        ]
    }

    func listModels(baseURL: String, apiKey: String) async throws -> [String] {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/v1/models",
            headers: headers(apiKey: apiKey)
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let decoded = try? JSONDecoder().decode(ModelsListResponse.self, from: data),
           let models = decoded.data {
            return models.map(\.id).sorted()
        }
        return AppSettings.defaultModels
    }

    /// Stream chat completions (OpenAI-compatible). Yields text deltas.
    func streamChat(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [ChatMessage],
        temperature: Double = 0.7
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = try JSONEncoder().encode(
                        ChatCompletionRequest(model: model, messages: messages, stream: true, temperature: temperature)
                    )
                    let (bytes, _) = try await client.stream(
                        base: baseURL,
                        path: "/v1/chat/completions",
                        headers: headers(apiKey: apiKey),
                        body: body
                    )
                    for try await line in bytes.lines {
                        for delta in SSEParser.deltas(from: line) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    // Fallback: non-stream request if stream fails hard on first attempt shape
                    do {
                        let text = try await nonStreamChat(
                            baseURL: baseURL,
                            apiKey: apiKey,
                            model: model,
                            messages: messages,
                            temperature: temperature
                        )
                        if !text.isEmpty { continuation.yield(text) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    func nonStreamChat(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [ChatMessage],
        temperature: Double = 0.7
    ) async throws -> String {
        let body = ChatCompletionRequest(model: model, messages: messages, stream: false, temperature: temperature)
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/v1/chat/completions",
            method: "POST",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: try JSONEncoder().encode(body)
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) {
            if let msg = decoded.error?.message { throw NetworkError.message(msg) }
            if let content = decoded.choices?.first?.message?.content { return content }
        }
        // Responses-style fallback text
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let outputText = obj["output_text"] as? String { return outputText }
            if let choices = obj["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        }
        throw NetworkError.message("无法解析模型回复")
    }
}
