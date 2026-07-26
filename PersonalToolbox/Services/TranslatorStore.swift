import Foundation
import OSLog

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

    /// Keychain key for a custom engine's API key. `apiKey` is intentionally excluded
    /// from `TranslatorEngine`'s `Codable` conformance so it never lands in the
    /// plaintext `translator_settings.json` file.
    private func keychainKey(for engineID: String) -> String {
        "translatorEngine.\(engineID).apiKey"
    }

    private func loadAPIKeysFromKeychain() {
        for index in engines.indices {
            engines[index].apiKey = KeychainStore.get(keychainKey(for: engines[index].id))
        }
    }

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
            loadAPIKeysFromKeychain()
            // Ensure sub2api engine stays in sync with empty fields
            syncSub2Placeholders(from: appSettings)
        } catch {
            applyDefaults(app: appSettings)
        }
    }

    private func applyDefaults(app: AppSettings) {
        let d = TranslatorSettings.makeDefault(
            sub2Base: app.sub2apiBaseURL,
            sub2Key: app.sub2apiAPIKey,
            model: app.preferredModel
        )
        engines = d.engines
        sourceLanguageCode = d.sourceLanguageCode
        targetLanguageCode = d.targetLanguageCode
        persist()
    }

    /// Strip Grok/Sub2API engines; keep Google as the only default.
    func syncSub2Placeholders(from app: AppSettings) {
        let before = engines.count
        engines.removeAll {
            $0.kind == .sub2api || $0.label.localizedCaseInsensitiveContains("grok")
        }
        if !engines.contains(where: { $0.kind == .google }) {
            engines.insert(
                TranslatorEngine(
                    id: "google",
                    kind: .google,
                    label: "Google 翻译",
                    systemImage: "g.circle",
                    enabled: true
                ),
                at: 0
            )
        }
        if engines.allSatisfy({ !$0.enabled }),
           let idx = engines.firstIndex(where: { $0.kind == .google }) {
            engines[idx].enabled = true
        }
        if engines.count != before {
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
        } catch {
            // 写盘失败 = 用户的引擎/语言设置静默丢失，至少留下线索。
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "PersonalToolbox", category: "Translator")
                .error("persist failed: \(error.localizedDescription)")
        }
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
        if let key = engine.apiKey, !key.isEmpty {
            KeychainStore.set(key, for: keychainKey(for: engine.id))
        } else {
            KeychainStore.delete(keychainKey(for: engine.id))
        }
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
        KeychainStore.delete(keychainKey(for: id))
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
