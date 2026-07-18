import Foundation

/// Translation backends: Sub2API / OpenAI-compatible AI, Google web translate.
enum TranslatorService {
    private static let googleEndpoint = "https://translate.googleapis.com/translate_a/single"

    private static let systemPrompt = [
        "You are a translation engine for an iOS translation panel.",
        "Always translate faithfully and naturally.",
        "Return translated text only.",
        "Do not answer the text, do not summarize, and do not add commentary.",
        "Preserve paragraph breaks, bullet structure, code blocks, URLs, emoji, and numbers.",
        "Do not omit, shorten, or paraphrase away any part of the input.",
        "Always output the full translation in the requested target language.",
        "Do not wrap the output in JSON or markdown fences."
    ].joined(separator: " ")

    // MARK: - Public

    static func translate(engine: TranslatorEngine, request: TranslatorRequest, appSettings: AppSettings) async throws -> String {
        let text = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NetworkError.message("请输入要翻译的文本") }

        switch engine.kind {
        case .google:
            return try await translateGoogle(request: request)
        case .sub2api, .aiApi:
            return try await translateAI(engine: engine, request: request, appSettings: appSettings)
        }
    }

    // MARK: - Google

    private static func mapGoogleLang(_ code: String, isSource: Bool) -> String {
        if code == "auto" { return isSource ? "auto" : code }
        if code == "zh-Hans" { return "zh-CN" }
        if code == "zh-Hant" { return "zh-TW" }
        return code
    }

    private static func translateGoogle(request: TranslatorRequest) async throws -> String {
        var comps = URLComponents(string: googleEndpoint)!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: mapGoogleLang(request.sourceLanguageCode, isSource: true)),
            URLQueryItem(name: "tl", value: mapGoogleLang(request.targetLanguageCode, isSource: false)),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: request.sourceText)
        ]
        guard let url = comps.url else { throw NetworkError.message("Google 翻译 URL 无效") }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.message("Google 翻译无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.message("Google 翻译失败（HTTP \(http.statusCode)）")
        }

        // Response: [[["translated","source",...],...], ...]
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [Any] else {
            throw NetworkError.message("Google 翻译返回格式无效")
        }
        var parts: [String] = []
        for item in sentences {
            guard let row = item as? [Any], let piece = row.first as? String else { continue }
            parts.append(piece)
        }
        let joined = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw NetworkError.message("Google 翻译没有返回可用译文") }
        return joined
    }

    // MARK: - AI (chunked)

    private static func translateAI(
        engine: TranslatorEngine,
        request: TranslatorRequest,
        appSettings: AppSettings
    ) async throws -> String {
        let resolved = resolveAIConfig(engine: engine, app: appSettings)
        let chunks = splitIntoChunks(request.sourceText, maxLength: 700)
        var outputs: [String] = []
        outputs.reserveCapacity(chunks.count)

        for (index, chunk) in chunks.enumerated() {
            let chunkRequest = TranslatorRequest(
                sourceText: chunk,
                sourceLanguageCode: request.sourceLanguageCode,
                targetLanguageCode: request.targetLanguageCode
            )
            let piece = try await translateAIChunk(
                config: resolved,
                request: chunkRequest,
                part: index + 1,
                total: chunks.count
            )
            outputs.append(piece)
        }
        return outputs.joined()
    }

    private struct AIConfig {
        var baseURL: String
        var apiKey: String
        var model: String
        var mode: TranslatorAiMode
    }

    private static func resolveAIConfig(engine: TranslatorEngine, app: AppSettings) -> AIConfig {
        let mode = engine.compatibilityMode ?? .newapi
        var base = (engine.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var key = (engine.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var model = (engine.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if engine.kind == .sub2api {
            if base.isEmpty { base = app.sub2apiBaseURL }
            if key.isEmpty { key = app.sub2apiAPIKey }
            if model.isEmpty { model = app.preferredModel }
        }

        if base.isEmpty {
            switch mode {
            case .openai: base = "https://api.openai.com"
            case .gemini: base = "https://generativelanguage.googleapis.com"
            case .newapi: break
            }
        }

        return AIConfig(baseURL: base, apiKey: key, model: model, mode: mode)
    }

    private static func translateAIChunk(
        config: AIConfig,
        request: TranslatorRequest,
        part: Int,
        total: Int
    ) async throws -> String {
        guard !config.baseURL.isEmpty else { throw NetworkError.message("请先配置 AI 接口地址") }
        guard !config.apiKey.isEmpty else { throw NetworkError.message("请先配置 API Key") }
        guard !config.model.isEmpty else { throw NetworkError.message("请先配置模型名称") }

        let sourceName = request.sourceLanguageCode == TranslatorLanguage.auto.code
            ? TranslatorLanguage.auto.promptName
            : TranslatorLanguage.find(request.sourceLanguageCode).promptName
        let targetName = TranslatorLanguage.find(request.targetLanguageCode).promptName

        var userLines = [
            "Source language: \(sourceName)",
            "Target language: \(targetName)",
            "Task: Translate the full text into the target language. Output translated text only.",
            ""
        ]
        if total > 1 {
            userLines.append("This is part \(part)/\(total) of a longer document. Translate this part only.")
            userLines.append("")
        }
        userLines.append("<text>")
        userLines.append(request.sourceText)
        userLines.append("</text>")

        let messages = [
            ChatMessage(role: .system, content: systemPrompt),
            ChatMessage(role: .user, content: userLines.joined(separator: "\n"))
        ]

        // Prefer shared Sub2API path for sub2api-compatible bases (newapi/openai chat completions).
        if config.mode == .gemini {
            return try await translateGeminiCompatible(config: config, messages: messages)
        }

        let text = try await Sub2APIService.shared.nonStreamChat(
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            model: config.model,
            messages: messages,
            temperature: 0.1
        )
        return cleanTranslation(text)
    }

    /// Gemini OpenAI-compatible path: /v1beta/openai/chat/completions
    private static func translateGeminiCompatible(config: AIConfig, messages: [ChatMessage]) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = base.hasSuffix("/v1beta/openai") ? "/chat/completions" : "/v1beta/openai/chat/completions"
        // Use NetworkClient with full base that includes path prefix via joining
        let urlString: String
        if base.contains("/v1beta") {
            urlString = base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
        } else {
            urlString = base + path
        }
        guard let url = URL(string: urlString) else { throw NetworkError.message("Gemini URL 无效") }

        let body = try JSONEncoder().encode(
            ChatCompletionRequest(model: config.model, messages: messages, stream: false, temperature: 0.1)
        )
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.message("Gemini 无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        if let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
           let content = decoded.choices?.first?.message?.content {
            return cleanTranslation(content)
        }
        throw NetworkError.message("无法解析 Gemini 回复")
    }

    private static func cleanTranslation(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    // MARK: - Chunking (from Translator.scripting)

    static func splitIntoChunks(_ text: String, maxLength: Int = 700) -> [String] {
        guard text.count > maxLength else { return [text] }
        var chunks: [String] = []
        var remaining = text
        while remaining.count > maxLength {
            let boundary = findChunkBoundary(remaining, maxLength: maxLength)
            let idx = remaining.index(remaining.startIndex, offsetBy: boundary)
            chunks.append(String(remaining[..<idx]))
            remaining = String(remaining[idx...])
        }
        if !remaining.isEmpty { chunks.append(remaining) }
        return chunks
    }

    private static func findChunkBoundary(_ text: String, maxLength: Int) -> Int {
        let prefix = String(text.prefix(maxLength))
        let minKeep = Int(Double(maxLength) * 0.55)
        let candidates = ["\n\n", "\n", "。", "！", "？", ". ", "! ", "? ", "；", ";", "，", ", ", " "]
        var best = -1
        for sep in candidates {
            if let r = prefix.range(of: sep, options: .backwards) {
                let offset = prefix.distance(from: prefix.startIndex, to: r.upperBound)
                if offset >= minKeep {
                    best = offset
                    break
                }
            }
        }
        return best > 0 ? best : maxLength
    }
}
