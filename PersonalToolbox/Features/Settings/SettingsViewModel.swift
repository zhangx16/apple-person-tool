import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var sub2Probe: ServiceProbeState = .unknown
    @Published private(set) var adminProbe: ServiceProbeState = .unknown
    @Published private(set) var ytProbe: ServiceProbeState = .unknown
    @Published private(set) var sublinkProbe: ServiceProbeState = .unknown
    @Published private(set) var komariProbe: ServiceProbeState = .unknown
    @Published private(set) var discoveredModels: [String] = []
    @Published var logoutNotice: String?

    private let settings: AppSettings
    private let sub2 = Sub2APIService.shared
    private let admin = Sub2AdminService.shared
    private let yt = YTService.shared
    private let sublink = SublinkService.shared
    private let komari = KomariService.shared
    private let network = NetworkClient.shared

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    var modelChoices: [String] {
        var set = Set(AppSettings.defaultModels)
        discoveredModels.filter { Sub2APIService.isTextModel($0) }.forEach { set.insert($0) }
        let preferred = settings.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty, Sub2APIService.isTextModel(preferred) { set.insert(preferred) }
        return set.sorted()
    }

    var imagineImageChoices: [String] {
        var set = Set(AppSettings.defaultImagineImageModels)
        discoveredModels.filter { Sub2APIService.isImagineImageModel($0) || $0.lowercased() == "grok-imagine" }
            .forEach { set.insert($0) }
        if !settings.preferredImagineImageModel.isEmpty { set.insert(settings.preferredImagineImageModel) }
        return set.sorted()
    }

    var imagineEditChoices: [String] {
        var set = Set(AppSettings.defaultImagineEditModels)
        discoveredModels.filter { Sub2APIService.isImagineEditModel($0) }.forEach { set.insert($0) }
        if !settings.preferredImagineEditModel.isEmpty { set.insert(settings.preferredImagineEditModel) }
        return set.sorted()
    }

    var imagineVideoChoices: [String] {
        var set = Set(AppSettings.defaultImagineVideoModels)
        discoveredModels.filter { Sub2APIService.isImagineVideoModel($0) }.forEach { set.insert($0) }
        if !settings.preferredImagineVideoModel.isEmpty { set.insert(settings.preferredImagineVideoModel) }
        return set.sorted()
    }

    func testSub2API() async {
        guard !sub2Probe.isProbing else { return }
        let base = settings.sub2apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = settings.sub2apiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !key.isEmpty else {
            sub2Probe = .failure("请填写 Base URL 与 Chat API Key")
            Haptics.error()
            return
        }
        sub2Probe = .probing
        let start = ContinuousClock.now
        do {
            let models = try await sub2.listModels(baseURL: base, apiKey: key)
            discoveredModels = models
            sub2Probe = .success(latencyMs: elapsedMs(since: start), detail: "\(models.count) 个模型")
            Haptics.success()
        } catch {
            sub2Probe = .failure(Self.chineseError(error))
            Haptics.error()
        }
    }

    func testAdmin() async {
        guard !adminProbe.isProbing else { return }
        let base = settings.sub2apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = settings.sub2apiAdminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !key.isEmpty else {
            adminProbe = .failure("请填写 Admin API Key")
            Haptics.error()
            return
        }
        adminProbe = .probing
        let start = ContinuousClock.now
        do {
            let detail = try await admin.probe(baseURL: base, adminKey: key)
            adminProbe = .success(latencyMs: elapsedMs(since: start), detail: detail)
            Haptics.success()
        } catch {
            adminProbe = .failure(Self.chineseError(error))
            Haptics.error()
        }
    }

    func testYT() async {
        guard !ytProbe.isProbing else { return }
        let base = settings.ytBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, settings.isYTConfigured else {
            ytProbe = .failure("请填写下载服务账号")
            Haptics.error()
            return
        }
        ytProbe = .probing
        let start = ContinuousClock.now
        do {
            await yt.logout()
            let ver = try await yt.version(
                baseURL: base,
                username: settings.ytUsername,
                password: settings.ytPassword
            )
            ytProbe = .success(latencyMs: elapsedMs(since: start), detail: "yt-dlp \(ver)")
            Haptics.success()
        } catch {
            ytProbe = .failure(Self.chineseError(error))
            Haptics.error()
        }
    }

    func testSublink() async {
        guard !sublinkProbe.isProbing else { return }
        let base = settings.sublinkBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            sublinkProbe = .failure("请填写 Base URL")
            Haptics.error()
            return
        }
        sublinkProbe = .probing
        let start = ContinuousClock.now
        do {
            // Captcha endpoint is unauthenticated health-ish signal.
            _ = try await sublink.fetchCaptcha(baseURL: base)
            // If already logged in, try overview.
            await sublink.restoreToken()
            if await sublink.hasToken {
                let detail = try await sublink.probe(baseURL: base)
                sublinkProbe = .success(latencyMs: elapsedMs(since: start), detail: detail)
            } else {
                sublinkProbe = .success(latencyMs: elapsedMs(since: start), detail: "验证码接口可用（需在服务页登录）")
            }
            Haptics.success()
        } catch {
            sublinkProbe = .failure(Self.chineseError(error))
            Haptics.error()
        }
    }

    func testKomari() async {
        guard !komariProbe.isProbing else { return }
        let base = settings.komariBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            komariProbe = .failure("请填写 Base URL")
            Haptics.error()
            return
        }
        komariProbe = .probing
        let start = ContinuousClock.now
        do {
            let detail = try await komari.probe(baseURL: base)
            komariProbe = .success(latencyMs: elapsedMs(since: start), detail: detail)
            Haptics.success()
        } catch {
            komariProbe = .failure(Self.chineseError(error))
            Haptics.error()
        }
    }

    func logoutAllSessions() async {
        network.clearCookies()
        await yt.logout()
        await sublink.logout()
        logoutNotice = "已清除下载 Token、SublinkX 会话与 Cookie。"
        Haptics.success()
    }

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        Int(start.duration(to: .now) / .milliseconds(1))
    }

    private static func chineseError(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
