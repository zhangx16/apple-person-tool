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
    /// Default Grok Imagine text-to-image model.
    @Published var preferredImagineImageModel: String {
        didSet { UserDefaults.standard.set(preferredImagineImageModel, forKey: Keys.preferredImagineImageModel) }
    }
    /// Default Grok Imagine image-edit model.
    @Published var preferredImagineEditModel: String {
        didSet { UserDefaults.standard.set(preferredImagineEditModel, forKey: Keys.preferredImagineEditModel) }
    }
    /// Default Grok Imagine text-to-video model.
    @Published var preferredImagineVideoModel: String {
        didSet { UserDefaults.standard.set(preferredImagineVideoModel, forKey: Keys.preferredImagineVideoModel) }
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
    /// Required when `mailUseExternalAPI` is true (external mode targets a mailbox).
    @Published var mailDefaultEmail: String {
        didSet { UserDefaults.standard.set(mailDefaultEmail, forKey: Keys.mailDefaultEmail) }
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

    /// `system` / `light` / `dark` — applied by app shell (PR-4 Settings UI).
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: Keys.appearance) }
    }
    /// Hide sensitive UI when app enters switcher / background.
    @Published var hideSensitiveInAppSwitcher: Bool {
        didSet { UserDefaults.standard.set(hideSensitiveInAppSwitcher, forKey: Keys.hideSensitiveInAppSwitcher) }
    }
    /// Optional Face ID / Touch ID gate. Default OFF (K12).
    @Published var requireBiometricUnlock: Bool {
        didSet { UserDefaults.standard.set(requireBiometricUnlock, forKey: Keys.requireBiometricUnlock) }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark
        var id: String { rawValue }
    }

    enum Keys {
        static let sub2apiBaseURL = "sub2apiBaseURL"
        static let sub2apiAPIKey = "sub2apiAPIKey"
        static let preferredModel = "preferredModel"
        static let preferredImagineImageModel = "preferredImagineImageModel"
        static let preferredImagineEditModel = "preferredImagineEditModel"
        static let preferredImagineVideoModel = "preferredImagineVideoModel"
        static let systemPrompt = "systemPrompt"
        static let mailBaseURL = "mailBaseURL"
        static let mailPassword = "mailPassword"
        static let mailExternalAPIKey = "mailExternalAPIKey"
        static let mailUseExternalAPI = "mailUseExternalAPI"
        static let mailDefaultEmail = "mailDefaultEmail"
        static let ytBaseURL = "ytBaseURL"
        static let ytUsername = "ytUsername"
        static let ytPassword = "ytPassword"
        static let appearance = "appearance"
        static let hideSensitiveInAppSwitcher = "hideSensitiveInAppSwitcher"
        static let requireBiometricUnlock = "requireBiometricUnlock"
    }

    /// Single source of truth for default chat model (preferredModel + ChatConversation).
    nonisolated static let defaultTextModel = "grok-4.3"
    nonisolated static let defaultImagineImageModel = "grok-imagine-image-quality"
    nonisolated static let defaultImagineEditModel = "grok-imagine-edit"
    nonisolated static let defaultImagineVideoModel = "grok-imagine-video-1.5"

    /// Pure data table; nonisolated so actors (e.g. Sub2APIService) can read without hopping to MainActor.
    /// Real xAI text model IDs (sub2api `models.go`); imagine models live on separate pickers.
    nonisolated static let defaultModels = [
        defaultTextModel,
        "grok-build-0.1",
        "grok-4.20-0309-reasoning",
        "grok-4.20-0309-non-reasoning",
        "grok-4.20-multi-agent-0309"
    ]

    nonisolated static let defaultImagineImageModels = [
        defaultImagineImageModel,
        "grok-imagine-image",
        "grok-imagine"
    ]

    nonisolated static let defaultImagineEditModels = [
        defaultImagineEditModel
    ]

    nonisolated static let defaultImagineVideoModels = [
        defaultImagineVideoModel,
        "grok-imagine-video"
    ]

    private init() {
        let defaults = UserDefaults.standard
        sub2apiBaseURL = defaults.string(forKey: Keys.sub2apiBaseURL) ?? "https://sub2api.996616.xyz"
        sub2apiAPIKey = KeychainStore.get(Keys.sub2apiAPIKey) ?? ""
        preferredModel = defaults.string(forKey: Keys.preferredModel) ?? Self.defaultTextModel
        preferredImagineImageModel = defaults.string(forKey: Keys.preferredImagineImageModel) ?? Self.defaultImagineImageModel
        preferredImagineEditModel = defaults.string(forKey: Keys.preferredImagineEditModel) ?? Self.defaultImagineEditModel
        preferredImagineVideoModel = defaults.string(forKey: Keys.preferredImagineVideoModel) ?? Self.defaultImagineVideoModel
        systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? "You are a helpful assistant."
        mailBaseURL = defaults.string(forKey: Keys.mailBaseURL) ?? "https://mail.996616.xyz"
        mailPassword = KeychainStore.get(Keys.mailPassword) ?? ""
        mailExternalAPIKey = KeychainStore.get(Keys.mailExternalAPIKey) ?? ""
        mailUseExternalAPI = defaults.object(forKey: Keys.mailUseExternalAPI) as? Bool ?? false
        mailDefaultEmail = defaults.string(forKey: Keys.mailDefaultEmail) ?? ""
        ytBaseURL = defaults.string(forKey: Keys.ytBaseURL) ?? "https://yt.996616.xyz"
        ytUsername = defaults.string(forKey: Keys.ytUsername) ?? "admin"
        ytPassword = KeychainStore.get(Keys.ytPassword) ?? ""
        appearance = defaults.string(forKey: Keys.appearance) ?? Appearance.system.rawValue
        hideSensitiveInAppSwitcher = defaults.object(forKey: Keys.hideSensitiveInAppSwitcher) as? Bool ?? false
        requireBiometricUnlock = defaults.object(forKey: Keys.requireBiometricUnlock) as? Bool ?? false
    }

    var isAIConfigured: Bool {
        !sub2apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sub2apiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isMailConfigured: Bool {
        if mailUseExternalAPI {
            return !mailExternalAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !mailDefaultEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !mailPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isYTConfigured: Bool {
        !ytUsername.isEmpty && !ytPassword.isEmpty
    }
}
