import Foundation
import Combine

/// Drives connectivity probes and logout-all for the Settings tab.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var sub2Probe: ServiceProbeState = .unknown
    @Published private(set) var mailProbe: ServiceProbeState = .unknown
    @Published private(set) var ytProbe: ServiceProbeState = .unknown
    /// Models discovered by the last successful sub2api probe (merged into preferred-model picker).
    @Published private(set) var discoveredModels: [String] = []
    @Published var logoutNotice: String?

    private let settings: AppSettings
    private let sub2 = Sub2APIService.shared
    private let mail = MailService.shared
    private let yt = YTService.shared
    private let network = NetworkClient.shared

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    /// Models for the preferred-model picker: discovered ∪ defaults, sorted, preferred first.
    var modelChoices: [String] {
        var set = Set(AppSettings.defaultModels)
        discoveredModels.forEach { set.insert($0) }
        let preferred = settings.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty { set.insert(preferred) }
        return set.sorted()
    }

    // MARK: - Probes

    func testSub2API() async {
        guard !sub2Probe.isProbing else { return }
        let base = settings.sub2apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = settings.sub2apiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            sub2Probe = .failure("请填写 Base URL")
            Haptics.error()
            return
        }
        guard !key.isEmpty else {
            sub2Probe = .failure("请填写 API Key")
            Haptics.error()
            return
        }

        sub2Probe = .probing
        let start = ContinuousClock.now
        do {
            let models = try await sub2.listModels(baseURL: base, apiKey: key)
            let ms = elapsedMs(since: start)
            discoveredModels = models
            let detail: String
            if models.isEmpty {
                detail = "已连通"
            } else {
                detail = "\(models.count) 个模型"
            }
            sub2Probe = .success(latencyMs: ms, detail: detail)
            // Prefer first remote model only if current preferred is empty.
            if settings.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let first = models.first {
                settings.preferredModel = first
            }
            Haptics.success()
        } catch {
            sub2Probe = .failure(Self.chineseError(error))
            Haptics.error()
        }
    }

    func testMail() async {
        guard !mailProbe.isProbing else { return }
        let base = settings.mailBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            mailProbe = .failure("请填写 Base URL")
            Haptics.error()
            return
        }

        mailProbe = .probing
        let start = ContinuousClock.now
        do {
            if settings.mailUseExternalAPI {
                let key = settings.mailExternalAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else {
                    mailProbe = .failure("请填写外部 API Key")
                    Haptics.error()
                    return
                }
                // List/detail require email; keep configured-check aligned with isMailConfigured.
                let email = settings.mailDefaultEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !email.isEmpty else {
                    mailProbe = .failure("请填写默认邮箱")
                    Haptics.error()
                    return
                }
                let ok = try await mail.externalHealth(baseURL: base, apiKey: key)
                let ms = elapsedMs(since: start)
                if ok {
                    let favorites = settings.normalizedMailFavoriteEmails.count
                    let detail = favorites > 0
                        ? "外部 API 健康 · \(email) + \(favorites) 收藏"
                        : "外部 API 健康 · \(email)"
                    mailProbe = .success(latencyMs: ms, detail: detail)
                    Haptics.success()
                } else {
                    mailProbe = .failure("健康检查未通过")
                    Haptics.error()
                }
            } else {
                let password = settings.mailPassword
                guard !password.isEmpty else {
                    mailProbe = .failure("请填写管理密码")
                    Haptics.error()
                    return
                }
                // Shared ensureSession; then list accounts to verify cookie path end-to-end.
                let page = try await mail.listAccounts(baseURL: base, password: password)
                let ms = elapsedMs(since: start)
                let total = page.totalCount ?? page.accounts.count
                mailProbe = .success(latencyMs: ms, detail: "\(total) 个邮箱账号")
                Haptics.success()
            }
        } catch {
            mailProbe = .failure(Self.chineseError(error))
            Haptics.error()
        }
    }

    func testYT() async {
        guard !ytProbe.isProbing else { return }
        let base = settings.ytBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = settings.ytUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = settings.ytPassword
        guard !base.isEmpty else {
            ytProbe = .failure("请填写 Base URL")
            Haptics.error()
            return
        }
        guard !user.isEmpty else {
            ytProbe = .failure("请填写用户名")
            Haptics.error()
            return
        }
        guard !password.isEmpty else {
            ytProbe = .failure("请填写密码")
            Haptics.error()
            return
        }

        ytProbe = .probing
        let start = ContinuousClock.now
        do {
            // Force a fresh login for the probe so credential changes are exercised.
            await yt.logout()
            try await yt.login(baseURL: base, username: user, password: password)
            let version = try await yt.version(baseURL: base, username: user, password: password)
            let ms = elapsedMs(since: start)
            let detail = version.isEmpty || version == "ok" ? "yt-dlp 已连通" : "yt-dlp \(version)"
            ytProbe = .success(latencyMs: ms, detail: detail)
            Haptics.success()
        } catch {
            ytProbe = .failure(Self.chineseError(error))
            Haptics.error()
        }
    }

    // MARK: - Logout all

    /// Clears mail cookies, mail session flag, and in-memory YT token.
    func logoutAllSessions() async {
        network.clearCookies()
        await mail.logout()
        await yt.logout()
        sub2Probe = .unknown
        mailProbe = .unknown
        ytProbe = .unknown
        logoutNotice = "已注销全部本地会话（邮件 Cookie 与下载 Token）"
        Haptics.success()
    }

    // MARK: - Helpers

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now)
        let ms = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        return max(0, Int(ms.rounded()))
    }

    static func chineseError(_ error: Error) -> String {
        if let net = error as? NetworkError {
            return net.errorDescription ?? "网络错误"
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "无网络连接"
            case NSURLErrorTimedOut: return "请求超时"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "无法连接服务器"
            case NSURLErrorSecureConnectionFailed: return "安全连接失败"
            default: break
            }
        }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "未知错误" : text
    }
}
