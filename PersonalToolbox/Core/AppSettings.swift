import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Defaults match this server's public domains.
    @Published var sub2apiBaseURL: String {
        didSet { UserDefaults.standard.set(sub2apiBaseURL, forKey: Keys.sub2apiBaseURL) }
    }
    @Published var sub2apiAPIKey: String {
        didSet { KeychainStore.set(sub2apiAPIKey, for: Keys.sub2apiAPIKey) }
    }
    @Published var preferredModel: String {
        didSet { UserDefaults.standard.set(preferredModel, forKey: Keys.preferredModel) }
    }
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: Keys.systemPrompt) }
    }

    @Published var mailBaseURL: String {
        didSet { UserDefaults.standard.set(mailBaseURL, forKey: Keys.mailBaseURL) }
    }
    @Published var mailPassword: String {
        didSet { KeychainStore.set(mailPassword, for: Keys.mailPassword) }
    }
    @Published var mailExternalAPIKey: String {
        didSet { KeychainStore.set(mailExternalAPIKey, for: Keys.mailExternalAPIKey) }
    }
    @Published var mailUseExternalAPI: Bool {
        didSet { UserDefaults.standard.set(mailUseExternalAPI, forKey: Keys.mailUseExternalAPI) }
    }

    @Published var ytBaseURL: String {
        didSet { UserDefaults.standard.set(ytBaseURL, forKey: Keys.ytBaseURL) }
    }
    @Published var ytUsername: String {
        didSet { UserDefaults.standard.set(ytUsername, forKey: Keys.ytUsername) }
    }
    @Published var ytPassword: String {
        didSet { KeychainStore.set(ytPassword, for: Keys.ytPassword) }
    }

    enum Keys {
        static let sub2apiBaseURL = "sub2apiBaseURL"
        static let sub2apiAPIKey = "sub2apiAPIKey"
        static let preferredModel = "preferredModel"
        static let systemPrompt = "systemPrompt"
        static let mailBaseURL = "mailBaseURL"
        static let mailPassword = "mailPassword"
        static let mailExternalAPIKey = "mailExternalAPIKey"
        static let mailUseExternalAPI = "mailUseExternalAPI"
        static let ytBaseURL = "ytBaseURL"
        static let ytUsername = "ytUsername"
        static let ytPassword = "ytPassword"
    }

    /// Pure data table; nonisolated so actors (e.g. Sub2APIService) can read without hopping to MainActor.
    nonisolated static let defaultModels = [
        "grok-4.5",
        "grok-4.3",
        "grok-4.20-0309-reasoning",
        "grok-4.20-0309-non-reasoning",
        "grok-build-0.1"
    ]

    private init() {
        let defaults = UserDefaults.standard
        sub2apiBaseURL = defaults.string(forKey: Keys.sub2apiBaseURL) ?? "https://sub2api.996616.xyz"
        sub2apiAPIKey = KeychainStore.get(Keys.sub2apiAPIKey) ?? ""
        preferredModel = defaults.string(forKey: Keys.preferredModel) ?? "grok-4.5"
        systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? "You are a helpful assistant."
        mailBaseURL = defaults.string(forKey: Keys.mailBaseURL) ?? "https://mail.996616.xyz"
        mailPassword = KeychainStore.get(Keys.mailPassword) ?? ""
        mailExternalAPIKey = KeychainStore.get(Keys.mailExternalAPIKey) ?? ""
        mailUseExternalAPI = defaults.object(forKey: Keys.mailUseExternalAPI) as? Bool ?? false
        ytBaseURL = defaults.string(forKey: Keys.ytBaseURL) ?? "https://yt.996616.xyz"
        ytUsername = defaults.string(forKey: Keys.ytUsername) ?? "admin"
        ytPassword = KeychainStore.get(Keys.ytPassword) ?? ""
    }

    var isAIConfigured: Bool {
        !sub2apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sub2apiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isMailConfigured: Bool {
        if mailUseExternalAPI {
            return !mailExternalAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !mailPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isYTConfigured: Bool {
        !ytUsername.isEmpty && !ytPassword.isEmpty
    }
}
