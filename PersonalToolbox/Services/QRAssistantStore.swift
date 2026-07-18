import Foundation
import UIKit

@MainActor
final class QRAssistantStore: ObservableObject {
    static let shared = QRAssistantStore()

    @Published private(set) var records: [QRRecord] = []
    @Published private(set) var settings: QRAssistantSettings = .default
    @Published private(set) var isLoaded = false
    @Published var lastError: String?

    private let dataFileName = "qr_assistant_data.json"
    private let maxRecords = 500

    private var dataURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(dataFileName)
    }

    private init() {}

    func load() {
        defer { isLoaded = true }
        guard FileManager.default.fileExists(atPath: dataURL.path) else {
            records = []
            settings = .default
            return
        }
        do {
            let data = try Data(contentsOf: dataURL)
            let decoded = try JSONDecoder().decode(QRAssistantData.self, from: data)
            records = decoded.records
            // Merge missing default keys if settings truncated
            var s = decoded.settings
            if s.redirectRules.isEmpty {
                s.redirectRules = QRRedirectDefaults.builtInRules
            }
            settings = s
        } catch {
            records = []
            settings = .default
        }
    }

    private func persist() {
        let payload = QRAssistantData(records: records, settings: settings, version: 1)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: dataURL, options: [.atomic])
        } catch {
            lastError = "保存失败"
        }
    }

    // MARK: - Records

    func addRecord(content: String, type: QRRecordType) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Dedupe consecutive identical scan
        if type == .scan,
           let first = records.first,
           first.type == .scan,
           first.content == trimmed {
            return
        }
        let record = QRRecord(content: trimmed, type: type)
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        persist()
        Haptics.success()
    }

    func deleteRecord(id: String) {
        records.removeAll { $0.id == id }
        persist()
        Haptics.light()
    }

    func deleteRecords(ids: Set<String>) {
        records.removeAll { ids.contains($0.id) }
        persist()
        Haptics.light()
    }

    func clearRecords() {
        records = []
        persist()
    }

    // MARK: - Settings / rules

    func updateSettings(_ newSettings: QRAssistantSettings) {
        settings = newSettings
        persist()
    }

    func setAutoScanOnOpen(_ value: Bool) {
        settings.autoScanOnOpen = value
        persist()
    }

    func setAutoRedirect(_ value: Bool) {
        settings.autoRedirect = value
        persist()
    }

    func setRedirectRules(_ rules: [QRRedirectRule]) {
        settings.redirectRules = rules
        persist()
    }

    func upsertRule(_ rule: QRRedirectRule) {
        if let idx = settings.redirectRules.firstIndex(where: { $0.id == rule.id }) {
            settings.redirectRules[idx] = rule
        } else {
            settings.redirectRules.append(rule)
        }
        persist()
        Haptics.success()
    }

    func deleteRule(id: String) {
        settings.redirectRules.removeAll { $0.id == id }
        persist()
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        settings.redirectRules.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func resetRulesToDefault() {
        settings.redirectRules = QRRedirectDefaults.builtInRules
        persist()
        Haptics.success()
    }

    func setFallback(enabled: Bool, scheme: String? = nil) {
        settings.fallbackEnabled = enabled
        if let scheme { settings.fallbackUrlScheme = scheme }
        persist()
    }

    func setSubscriptionUrl(_ url: String) {
        settings.subscriptionUrl = url
        persist()
    }

    /// Fetch remote JSON array of rules and merge.
    func refreshSubscription() async {
        let raw = settings.subscriptionUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else {
            lastError = "订阅地址无效"
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                lastError = "订阅请求失败 (\(http.statusCode))"
                return
            }
            let remote = try JSONDecoder().decode([QRRedirectRule].self, from: data)
            settings.redirectRules = QRRedirectEngine.mergeRemote(
                local: settings.redirectRules,
                remote: remote
            )
            persist()
            lastError = nil
            Haptics.success()
        } catch {
            lastError = "订阅拉取失败：\(error.localizedDescription)"
            Haptics.error()
        }
    }

    // MARK: - Open / redirect

    @discardableResult
    func tryRedirect(content: String) -> Bool {
        guard settings.autoRedirect else { return false }
        if let rule = QRRedirectEngine.match(content: content, rules: settings.redirectRules),
           let url = QRRedirectEngine.resolveScheme(rule.urlScheme, content: content) {
            open(url)
            return true
        }
        if settings.fallbackEnabled {
            let scheme = settings.fallbackUrlScheme.trimmingCharacters(in: .whitespacesAndNewlines)
            if !scheme.isEmpty, let url = QRRedirectEngine.resolveScheme(scheme, content: content) {
                open(url)
                return true
            }
        }
        return false
    }

    func openContent(_ content: String) {
        if let http = QRRedirectEngine.openableHTTPURL(from: content) {
            open(http)
            return
        }
        if let rule = QRRedirectEngine.match(content: content, rules: settings.redirectRules),
           let url = QRRedirectEngine.resolveScheme(rule.urlScheme, content: content) {
            open(url)
            return
        }
        if let url = URL(string: content) {
            open(url)
        }
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
