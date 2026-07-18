import Foundation

@MainActor
final class TranslatorStore: ObservableObject {
    static let shared = TranslatorStore()

    @Published private(set) var engines: [TranslatorEngine] = []
    @Published var sourceLanguageCode: String = TranslatorLanguage.auto.code
    @Published var targetLanguageCode: String = "zh-Hans"
    @Published private(set) var isLoaded = false

    private let fileName = "translator_settings.json"

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private init() {}

    func load(appSettings: AppSettings) {
        defer { isLoaded = true }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            applyDefaults(app: appSettings)
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(TranslatorSettings.self, from: data)
            engines = decoded.engines
            sourceLanguageCode = decoded.sourceLanguageCode
            targetLanguageCode = decoded.targetLanguageCode
            // Ensure sub2api engine stays in sync with empty fields
            syncSub2Placeholders(from: appSettings)
        } catch {
            applyDefaults(app: appSettings)
        }
    }

    private func applyDefaults(app: AppSettings) {
        let d = TranslatorSettings.default(app: app)
        engines = d.engines
        sourceLanguageCode = d.sourceLanguageCode
        targetLanguageCode = d.targetLanguageCode
        persist()
    }

    /// Fill blank sub2api fields from AppSettings without overwriting custom values.
    func syncSub2Placeholders(from app: AppSettings) {
        guard let idx = engines.firstIndex(where: { $0.kind == .sub2api }) else {
            // Ensure at least one sub2api engine exists
            let defaults = TranslatorEngine.defaults(
                sub2Base: app.sub2apiBaseURL,
                sub2Key: app.sub2apiAPIKey,
                model: app.preferredModel
            )
            if let sub = defaults.first(where: { $0.kind == .sub2api }) {
                engines.insert(sub, at: 0)
                persist()
            }
            return
        }
        var e = engines[idx]
        var changed = false
        if (e.baseURL ?? "").isEmpty {
            e.baseURL = app.sub2apiBaseURL
            changed = true
        }
        if (e.apiKey ?? "").isEmpty, !app.sub2apiAPIKey.isEmpty {
            e.apiKey = app.sub2apiAPIKey
            changed = true
        }
        if (e.model ?? "").isEmpty {
            e.model = app.preferredModel
            changed = true
        }
        if changed {
            engines[idx] = e
            persist()
        }
    }

    private func persist() {
        let payload = TranslatorSettings(
            engines: engines,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode
        )
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: [.atomic])
        } catch {}
    }

    func saveLanguages() {
        persist()
    }

    func setEngineEnabled(id: String, enabled: Bool) {
        guard let idx = engines.firstIndex(where: { $0.id == id }) else { return }
        engines[idx].enabled = enabled
        persist()
    }

    func upsertEngine(_ engine: TranslatorEngine) {
        if let idx = engines.firstIndex(where: { $0.id == engine.id }) {
            engines[idx] = engine
        } else {
            engines.append(engine)
        }
        persist()
        Haptics.success()
    }

    func deleteEngine(id: String) {
        // Keep at least one engine
        guard engines.count > 1 else { return }
        engines.removeAll { $0.id == id }
        persist()
        Haptics.light()
    }

    func moveEngines(from: IndexSet, to: Int) {
        engines.move(fromOffsets: from, toOffset: to)
        persist()
    }

    func resetToDefaults(app: AppSettings) {
        applyDefaults(app: app)
        Haptics.success()
    }

    var enabledEngines: [TranslatorEngine] {
        engines.filter(\.enabled)
    }

    func swapLanguages() {
        if sourceLanguageCode == TranslatorLanguage.auto.code { return }
        let s = sourceLanguageCode
        sourceLanguageCode = targetLanguageCode
        targetLanguageCode = s
        persist()
    }
}
