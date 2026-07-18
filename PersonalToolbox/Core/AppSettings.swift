import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Sub2API (chat + admin monitor)

    @Published var sub2apiBaseURL: String {
        didSet { UserDefaults.standard.set(sub2apiBaseURL, forKey: Keys.sub2apiBaseURL) }
    }
    /// User / gateway API key for chat completions.
    @Published var sub2apiAPIKey: String {
        didSet { KeychainStore.set(sub2apiAPIKey, for: Keys.sub2apiAPIKey) }
    }
    /// Admin API key for `/api/v1/admin/*` (header `x-api-key`), used by 监控 tab.
    @Published var sub2apiAdminAPIKey: String {
        didSet { KeychainStore.set(sub2apiAdminAPIKey, for: Keys.sub2apiAdminAPIKey) }
    }
    @Published var preferredModel: String {
        didSet { UserDefaults.standard.set(preferredModel, forKey: Keys.preferredModel) }
    }
    @Published var preferredImagineImageModel: String {
        didSet { UserDefaults.standard.set(preferredImagineImageModel, forKey: Keys.preferredImagineImageModel) }
    }
    @Published var preferredImagineEditModel: String {
        didSet { UserDefaults.standard.set(preferredImagineEditModel, forKey: Keys.preferredImagineEditModel) }
    }
    @Published var preferredImagineVideoModel: String {
        didSet { UserDefaults.standard.set(preferredImagineVideoModel, forKey: Keys.preferredImagineVideoModel) }
    }
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: Keys.systemPrompt) }
    }

    // MARK: - yt-dlp

    @Published var ytBaseURL: String {
        didSet { UserDefaults.standard.set(ytBaseURL, forKey: Keys.ytBaseURL) }
    }
    @Published var ytUsername: String {
        didSet { UserDefaults.standard.set(ytUsername, forKey: Keys.ytUsername) }
    }
    @Published var ytPassword: String {
        didSet { KeychainStore.set(ytPassword, for: Keys.ytPassword) }
    }

    // MARK: - SublinkX

    @Published var sublinkBaseURL: String {
        didSet { UserDefaults.standard.set(sublinkBaseURL, forKey: Keys.sublinkBaseURL) }
    }
    @Published var sublinkUsername: String {
        didSet { UserDefaults.standard.set(sublinkUsername, forKey: Keys.sublinkUsername) }
    }
    @Published var sublinkPassword: String {
        didSet { KeychainStore.set(sublinkPassword, for: Keys.sublinkPassword) }
    }

    // MARK: - Komari

    @Published var komariBaseURL: String {
        didSet { UserDefaults.standard.set(komariBaseURL, forKey: Keys.komariBaseURL) }
    }

    // MARK: - Cloudflare (CFPanel-style)

    /// API Token (Bearer) or Global API Key when email is set.
    @Published var cloudflareAPIToken: String {
        didSet { KeychainStore.set(cloudflareAPIToken, for: Keys.cloudflareAPIToken) }
    }
    /// Optional: when non-empty, auth uses X-Auth-Email + X-Auth-Key.
    @Published var cloudflareEmail: String {
        didSet { UserDefaults.standard.set(cloudflareEmail, forKey: Keys.cloudflareEmail) }
    }
    @Published var cloudflareAccountId: String {
        didSet { UserDefaults.standard.set(cloudflareAccountId, forKey: Keys.cloudflareAccountId) }
    }
    @Published var cloudflareAccountName: String {
        didSet { UserDefaults.standard.set(cloudflareAccountName, forKey: Keys.cloudflareAccountName) }
    }

    // MARK: - 财联社电报

    /// RSS/Atom feed URL (default pyrsshub cls/telegraph).
    @Published var clsFeedURL: String {
        didSet { UserDefaults.standard.set(clsFeedURL, forKey: Keys.clsFeedURL) }
    }

    // MARK: - Tab project selection (bottom tabs)

    /// `MonitorProject.rawValue`: sub2 | cloudflare
    @Published var monitorProjectRaw: String {
        didSet { UserDefaults.standard.set(monitorProjectRaw, forKey: Keys.monitorProjectRaw) }
    }
    /// `DownloadProject.rawValue`: youtube | douyin
    @Published var downloadProjectRaw: String {
        didSet { UserDefaults.standard.set(downloadProjectRaw, forKey: Keys.downloadProjectRaw) }
    }

    // MARK: - Appearance / privacy

    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: Keys.appearance) }
    }
    @Published var hideSensitiveInAppSwitcher: Bool {
        didSet { UserDefaults.standard.set(hideSensitiveInAppSwitcher, forKey: Keys.hideSensitiveInAppSwitcher) }
    }
    @Published var requireBiometricUnlock: Bool {
        didSet { UserDefaults.standard.set(requireBiometricUnlock, forKey: Keys.requireBiometricUnlock) }
    }

    // MARK: - Notifications

    /// Local notification when a download finishes (YouTube queue or Douyin).
    @Published var notifyDownloadCompleted: Bool {
        didSet { UserDefaults.standard.set(notifyDownloadCompleted, forKey: Keys.notifyDownloadCompleted) }
    }

    // MARK: - 快递100 realtime API

    @Published var kuaidi100Customer: String {
        didSet { UserDefaults.standard.set(kuaidi100Customer, forKey: Keys.kuaidi100Customer) }
    }
    @Published var kuaidi100Key: String {
        didSet { KeychainStore.set(kuaidi100Key, for: Keys.kuaidi100Key) }
    }

    // MARK: - 快手直播（可选登录 Cookie，用于弹幕）

    /// 浏览器登录 live.kuaishou.com 后复制的 Cookie 全文。
    @Published var kuaishouCookie: String {
        didSet { UserDefaults.standard.set(kuaishouCookie, forKey: Keys.kuaishouCookie) }
    }
    /// 可选 Kww / kwfv1 派生值；多数情况下从 Cookie 的 kwfv1 自动解析。
    @Published var kuaishouKww: String {
        didSet { UserDefaults.standard.set(kuaishouKww, forKey: Keys.kuaishouKww) }
    }

    // MARK: - 抖音直播（Cookie，搜索/部分房间需要）

    /// 浏览器登录 live.douyin.com 后复制的 Cookie（含 ttwid 等）。
    @Published var douyinLiveCookie: String {
        didSet { UserDefaults.standard.set(douyinLiveCookie, forKey: Keys.douyinLiveCookie) }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
    }

    enum Keys {
        static let sub2apiBaseURL = "sub2apiBaseURL"
        static let sub2apiAPIKey = "sub2apiAPIKey"
        static let sub2apiAdminAPIKey = "sub2apiAdminAPIKey"
        static let preferredModel = "preferredModel"
        static let preferredImagineImageModel = "preferredImagineImageModel"
        static let preferredImagineEditModel = "preferredImagineEditModel"
        static let preferredImagineVideoModel = "preferredImagineVideoModel"
        static let systemPrompt = "systemPrompt"
        static let ytBaseURL = "ytBaseURL"
        static let ytUsername = "ytUsername"
        static let ytPassword = "ytPassword"
        static let sublinkBaseURL = "sublinkBaseURL"
        static let sublinkUsername = "sublinkUsername"
        static let sublinkPassword = "sublinkPassword"
        static let komariBaseURL = "komariBaseURL"
        static let cloudflareAPIToken = "cloudflareAPIToken"
        static let cloudflareEmail = "cloudflareEmail"
        static let cloudflareAccountId = "cloudflareAccountId"
        static let cloudflareAccountName = "cloudflareAccountName"
        static let clsFeedURL = "clsFeedURL"
        static let monitorProjectRaw = "monitorProjectRaw"
        static let downloadProjectRaw = "downloadProjectRaw"
        static let appearance = "appearance"
        static let hideSensitiveInAppSwitcher = "hideSensitiveInAppSwitcher"
        static let requireBiometricUnlock = "requireBiometricUnlock"
        static let notifyDownloadCompleted = "notifyDownloadCompleted"
        static let kuaidi100Customer = "kuaidi100Customer"
        static let kuaidi100Key = "kuaidi100Key"
        static let kuaishouCookie = "kuaishouCookie"
        static let kuaishouKww = "kuaishouKww"
        static let douyinLiveCookie = "douyinLiveCookie"
    }

    nonisolated static let defaultTextModel = "grok-4.3"
    nonisolated static let defaultImagineImageModel = "grok-imagine-image-quality"
    nonisolated static let defaultImagineEditModel = "grok-imagine-edit"
    nonisolated static let defaultImagineVideoModel = "grok-imagine-video-1.5"

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

    nonisolated static let defaultImagineEditModels = [defaultImagineEditModel]
    nonisolated static let defaultImagineVideoModels = [
        defaultImagineVideoModel,
        "grok-imagine-video"
    ]

    private init() {
        let d = UserDefaults.standard
        sub2apiBaseURL = d.string(forKey: Keys.sub2apiBaseURL) ?? "https://sub2api.996616.xyz"
        sub2apiAPIKey = KeychainStore.get(Keys.sub2apiAPIKey) ?? ""
        sub2apiAdminAPIKey = KeychainStore.get(Keys.sub2apiAdminAPIKey) ?? ""
        preferredModel = d.string(forKey: Keys.preferredModel) ?? Self.defaultTextModel
        preferredImagineImageModel = d.string(forKey: Keys.preferredImagineImageModel) ?? Self.defaultImagineImageModel
        preferredImagineEditModel = d.string(forKey: Keys.preferredImagineEditModel) ?? Self.defaultImagineEditModel
        preferredImagineVideoModel = d.string(forKey: Keys.preferredImagineVideoModel) ?? Self.defaultImagineVideoModel
        systemPrompt = d.string(forKey: Keys.systemPrompt) ?? "You are a helpful assistant."
        ytBaseURL = d.string(forKey: Keys.ytBaseURL) ?? "https://yt.996616.xyz"
        ytUsername = d.string(forKey: Keys.ytUsername) ?? "admin"
        ytPassword = KeychainStore.get(Keys.ytPassword) ?? ""
        sublinkBaseURL = d.string(forKey: Keys.sublinkBaseURL) ?? "https://sub.996616.xyz"
        sublinkUsername = d.string(forKey: Keys.sublinkUsername) ?? "admin"
        sublinkPassword = KeychainStore.get(Keys.sublinkPassword) ?? ""
        komariBaseURL = d.string(forKey: Keys.komariBaseURL) ?? "https://komari.996616.xyz"
        cloudflareAPIToken = KeychainStore.get(Keys.cloudflareAPIToken) ?? ""
        cloudflareEmail = d.string(forKey: Keys.cloudflareEmail) ?? ""
        cloudflareAccountId = d.string(forKey: Keys.cloudflareAccountId) ?? ""
        cloudflareAccountName = d.string(forKey: Keys.cloudflareAccountName) ?? ""
        clsFeedURL = d.string(forKey: Keys.clsFeedURL)
            ?? "https://pyrsshub.vercel.app/cls/telegraph/"
        monitorProjectRaw = d.string(forKey: Keys.monitorProjectRaw) ?? "sub2"
        downloadProjectRaw = d.string(forKey: Keys.downloadProjectRaw) ?? "youtube"
        appearance = d.string(forKey: Keys.appearance) ?? Appearance.system.rawValue
        hideSensitiveInAppSwitcher = d.object(forKey: Keys.hideSensitiveInAppSwitcher) as? Bool ?? false
        requireBiometricUnlock = d.object(forKey: Keys.requireBiometricUnlock) as? Bool ?? false
        notifyDownloadCompleted = d.object(forKey: Keys.notifyDownloadCompleted) as? Bool ?? true
        // 快递100：仅从本机 UserDefaults / Keychain 读取，不在仓库中预置密钥
        kuaidi100Customer = d.string(forKey: Keys.kuaidi100Customer) ?? ""
        kuaidi100Key = KeychainStore.get(Keys.kuaidi100Key) ?? ""
        kuaishouCookie = d.string(forKey: Keys.kuaishouCookie) ?? ""
        kuaishouKww = d.string(forKey: Keys.kuaishouKww) ?? ""
        douyinLiveCookie = d.string(forKey: Keys.douyinLiveCookie) ?? ""
    }

    var isAIConfigured: Bool {
        !sub2apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sub2apiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAdminConfigured: Bool {
        !sub2apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sub2apiAdminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isYTConfigured: Bool {
        !ytUsername.isEmpty && !ytPassword.isEmpty
    }

    var isSublinkConfigured: Bool {
        !sublinkUsername.isEmpty && !sublinkPassword.isEmpty
    }

    var isCloudflareConfigured: Bool {
        !cloudflareAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
