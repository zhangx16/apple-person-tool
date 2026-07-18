import Foundation
import SwiftUI

// MARK: - Domain (aligned with Translator.scripting / BlackCCCat Translator)

struct TranslatorLanguage: Identifiable, Hashable, Sendable {
    var id: String { code }
    let code: String
    let label: String
    let promptName: String

    static let auto = TranslatorLanguage(code: "auto", label: "自动检测", promptName: "Auto detect")

    static let all: [TranslatorLanguage] = [
        .auto,
        .init(code: "zh-Hans", label: "简体中文", promptName: "Simplified Chinese"),
        .init(code: "zh-Hant", label: "繁体中文", promptName: "Traditional Chinese"),
        .init(code: "en", label: "英语", promptName: "English"),
        .init(code: "ja", label: "日语", promptName: "Japanese"),
        .init(code: "ko", label: "韩语", promptName: "Korean"),
        .init(code: "fr", label: "法语", promptName: "French"),
        .init(code: "de", label: "德语", promptName: "German"),
        .init(code: "es", label: "西班牙语", promptName: "Spanish"),
        .init(code: "ru", label: "俄语", promptName: "Russian"),
        .init(code: "it", label: "意大利语", promptName: "Italian"),
        .init(code: "pt", label: "葡萄牙语", promptName: "Portuguese"),
        .init(code: "ar", label: "阿拉伯语", promptName: "Arabic"),
        .init(code: "th", label: "泰语", promptName: "Thai"),
        .init(code: "vi", label: "越南语", promptName: "Vietnamese"),
        .init(code: "id", label: "印尼语", promptName: "Indonesian"),
        .init(code: "hi", label: "印地语", promptName: "Hindi"),
        .init(code: "tr", label: "土耳其语", promptName: "Turkish"),
        .init(code: "pl", label: "波兰语", promptName: "Polish"),
        .init(code: "nl", label: "荷兰语", promptName: "Dutch"),
        .init(code: "uk", label: "乌克兰语", promptName: "Ukrainian")
    ]

    static func find(_ code: String) -> TranslatorLanguage {
        all.first { $0.code == code } ?? all[1]
    }
}

enum TranslatorEngineKind: String, Codable, Sendable {
    case sub2api
    case google
    case aiApi = "ai_api"
}

enum TranslatorAiMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case newapi
    case openai
    case gemini

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newapi: return "NewAPI / OpenAI 兼容"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini (OpenAI 兼容路径)"
        }
    }
}

struct TranslatorEngine: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var kind: TranslatorEngineKind
    var label: String
    var systemImage: String
    var enabled: Bool
    /// For ai_api / optional override on sub2api
    var apiKey: String?
    var baseURL: String?
    var model: String?
    var compatibilityMode: TranslatorAiMode?

    static func defaults(sub2Base: String, sub2Key: String, model: String) -> [TranslatorEngine] {
        [
            TranslatorEngine(
                id: "sub2api",
                kind: .sub2api,
                label: "Sub2API (Grok)",
                systemImage: "sparkles",
                enabled: true,
                apiKey: sub2Key.isEmpty ? nil : sub2Key,
                baseURL: sub2Base,
                model: model,
                compatibilityMode: .newapi
            ),
            TranslatorEngine(
                id: "google",
                kind: .google,
                label: "Google 网页翻译",
                systemImage: "g.circle",
                enabled: true
            )
        ]
    }
}

struct TranslatorSettings: Codable, Sendable {
    var engines: [TranslatorEngine]
    var sourceLanguageCode: String
    var targetLanguageCode: String

    static func makeDefault(sub2Base: String, sub2Key: String, model: String) -> TranslatorSettings {
        TranslatorSettings(
            engines: TranslatorEngine.defaults(
                sub2Base: sub2Base,
                sub2Key: sub2Key,
                model: model
            ),
            sourceLanguageCode: TranslatorLanguage.auto.code,
            targetLanguageCode: "zh-Hans"
        )
    }
}

struct TranslatorRequest: Sendable {
    var sourceText: String
    var sourceLanguageCode: String
    var targetLanguageCode: String
}

struct TranslatorEngineResult: Identifiable, Hashable {
    var id: String { engineId }
    var engineId: String
    var engineName: String
    var systemImage: String
    var translatedText: String
    var errorText: String
    var isTranslating: Bool
}

enum TranslatorAccent {
    static let color = Color(hex: 0x007AFF)
}
