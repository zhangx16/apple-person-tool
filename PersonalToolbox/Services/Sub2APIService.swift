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
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        if let decoded = try? JSONDecoder().decode(ModelsListResponse.self, from: data),
           let models = decoded.data {
            return models.map(\.id).sorted()
        }
        return AppSettings.defaultModels
    }

    /// Text-only model IDs (exclude Grok Imagine family).
    static func isTextModel(_ id: String) -> Bool {
        !isImagineModel(id)
    }

    /// Grok Imagine family (image / edit / video).
    static func isImagineModel(_ id: String) -> Bool {
        id.localizedCaseInsensitiveContains("imagine")
    }

    /// Imagine models suitable for text-to-image (exclude pure edit/video IDs when possible).
    static func isImagineImageModel(_ id: String) -> Bool {
        guard isImagineModel(id) else { return false }
        let lower = id.lowercased()
        if lower.contains("video") { return false }
        if lower.contains("edit") { return false }
        return true
    }

    static func isImagineEditModel(_ id: String) -> Bool {
        guard isImagineModel(id) else { return false }
        return id.lowercased().contains("edit") || id.lowercased() == "grok-imagine-edit"
    }

    static func isImagineVideoModel(_ id: String) -> Bool {
        guard isImagineModel(id) else { return false }
        return id.lowercased().contains("video")
    }

    /// Stream chat completions (OpenAI-compatible). Yields text deltas.
    ///
    /// Cancellation: consumer cancel / `onTermination` cancels the producer `Task`,
    /// which cancels the underlying `URLSession` bytes request.
    /// Fallback: non-stream only when the stream failed with **zero** deltas
    /// (partial content never falls back; cancellation never falls back).
    func streamChat(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [ChatMessage],
        temperature: Double = 0.7
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var receivedAnyDelta = false
                do {
                    try Task.checkCancellation()
                    let body = try JSONEncoder().encode(
                        ChatCompletionRequest(model: model, messages: messages, stream: true, temperature: temperature)
                    )
                    let (bytes, _) = try await self.client.stream(
                        base: baseURL,
                        path: "/v1/chat/completions",
                        headers: self.headers(apiKey: apiKey),
                        body: body
                    )

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for delta in SSEParser.deltas(from: line) {
                            receivedAnyDelta = true
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    // Zero-delta hard failure only → one non-stream fallback.
                    guard !receivedAnyDelta else {
                        continuation.finish(throwing: error)
                        return
                    }
                    do {
                        try Task.checkCancellation()
                        let text = try await self.nonStreamChat(
                            baseURL: baseURL,
                            apiKey: apiKey,
                            model: model,
                            messages: messages,
                            temperature: temperature
                        )
                        if !text.isEmpty { continuation.yield(text) }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
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
        // Long LLM completion — use SSE-class timeouts (120s/600s), not short REST.
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/v1/chat/completions",
            method: "POST",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: try JSONEncoder().encode(body),
            profile: .sse
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
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
