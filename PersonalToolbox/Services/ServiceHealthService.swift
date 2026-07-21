import Foundation

struct ServiceHealthItem: Identifiable, Hashable {
    enum Status: String, Hashable {
        case unknown, ok, fail, skip
        var label: String {
            switch self {
            case .unknown: return "未检测"
            case .ok: return "正常"
            case .fail: return "异常"
            case .skip: return "未配置"
            }
        }
    }

    var id: String
    var title: String
    var brand: ServiceBrand
    var status: Status
    var latencyMs: Int?
    var detail: String
}

@MainActor
final class ServiceHealthService: ObservableObject {
    static let shared = ServiceHealthService()

    @Published private(set) var items: [ServiceHealthItem] = []
    @Published private(set) var isProbing = false
    @Published private(set) var lastProbedAt: Date?

    private let settings = AppSettings.shared

    private init() {
        items = Self.skeleton(settings: settings)
    }

    private static func skeleton(settings: AppSettings) -> [ServiceHealthItem] {
        [
            .init(id: "sub2", title: "Sub2API / 翻译", brand: .sub2, status: settings.isAIConfigured ? .unknown : .skip, latencyMs: nil, detail: settings.sub2apiBaseURL),
            .init(id: "admin", title: "Sub2API 监控", brand: .sub2, status: settings.isAdminConfigured ? .unknown : .skip, latencyMs: nil, detail: "Admin API"),
            .init(id: "checkin", title: "签到服务", brand: .checkin, status: settings.isCheckinConfigured ? .unknown : .skip, latencyMs: nil, detail: settings.checkinBaseURL),
            .init(id: "yt", title: "YouTube 下载", brand: .youtube, status: settings.isYTConfigured ? .unknown : .skip, latencyMs: nil, detail: settings.ytBaseURL),
            .init(id: "sublink", title: "SublinkX", brand: .sublink, status: settings.isSublinkConfigured ? .unknown : .skip, latencyMs: nil, detail: settings.sublinkBaseURL),
            .init(id: "komari", title: "Komari", brand: .komari, status: settings.komariBaseURL.isEmpty ? .skip : .unknown, latencyMs: nil, detail: settings.komariBaseURL),
            .init(id: "cf", title: "Cloudflare", brand: .cloudflare, status: settings.isCloudflareConfigured ? .unknown : .skip, latencyMs: nil, detail: "API Token")
        ]
    }

    func probeAll() async {
        guard !isProbing else { return }
        isProbing = true
        defer {
            isProbing = false
            lastProbedAt = Date()
        }
        var next = Self.skeleton(settings: settings)

        func apply(_ id: String, _ status: ServiceHealthItem.Status, _ ms: Int?, _ detail: String) {
            if let idx = next.firstIndex(where: { $0.id == id }) {
                next[idx].status = status
                next[idx].latencyMs = ms
                next[idx].detail = detail
            }
        }

        // Sequential probes — simpler MainActor isolation than task groups.
        if settings.isAIConfigured {
            let r = await probeSub2(); apply(r.0, r.1, r.2, r.3)
        }
        if settings.isAdminConfigured {
            let r = await probeAdmin(); apply(r.0, r.1, r.2, r.3)
        }
        if settings.isCheckinConfigured {
            let r = await probeCheckin(); apply(r.0, r.1, r.2, r.3)
        }
        if settings.isYTConfigured {
            let r = await probeYT(); apply(r.0, r.1, r.2, r.3)
        }
        if settings.isSublinkConfigured {
            let r = await probeSublink(); apply(r.0, r.1, r.2, r.3)
        }
        if !settings.komariBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let r = await probeKomari(); apply(r.0, r.1, r.2, r.3)
        }
        if settings.isCloudflareConfigured {
            let r = await probeCF(); apply(r.0, r.1, r.2, r.3)
        }
        items = next
    }

    private func probeSub2() async -> (String, ServiceHealthItem.Status, Int?, String) {
        let start = ContinuousClock.now
        do {
            let models = try await Sub2APIService.shared.listModels(
                baseURL: settings.sub2apiBaseURL,
                apiKey: settings.sub2apiAPIKey
            )
            let ms = Int(start.duration(to: .now) / .milliseconds(1))
            return ("sub2", .ok, ms, "\(models.count) 个模型")
        } catch {
            return ("sub2", .fail, nil, error.localizedDescription)
        }
    }

    private func probeAdmin() async -> (String, ServiceHealthItem.Status, Int?, String) {
        let start = ContinuousClock.now
        do {
            let detail = try await Sub2AdminService.shared.probe(
                baseURL: settings.sub2apiBaseURL,
                adminKey: settings.sub2apiAdminAPIKey
            )
            let ms = Int(start.duration(to: .now) / .milliseconds(1))
            return ("admin", .ok, ms, detail)
        } catch {
            return ("admin", .fail, nil, error.localizedDescription)
        }
    }

    private func probeCheckin() async -> (String, ServiceHealthItem.Status, Int?, String) {
        let start = ContinuousClock.now
        do {
            let health = try await CheckinService.shared.health(
                baseURL: settings.checkinBaseURL,
                apiToken: settings.checkinAPIToken
            )
            let summary = try await CheckinService.shared.summary(
                baseURL: settings.checkinBaseURL,
                apiToken: settings.checkinAPIToken
            )
            let ms = Int(start.duration(to: .now) / .milliseconds(1))
            let total = summary.counts?.totalValue ?? 0
            let healthy = summary.counts?.healthyValue ?? 0
            let auth = health.auth ?? "token"
            return ("checkin", .ok, ms, "\(auth) · \(healthy)/\(total) 正常")
        } catch {
            return ("checkin", .fail, nil, error.localizedDescription)
        }
    }

    private func probeYT() async -> (String, ServiceHealthItem.Status, Int?, String) {
        let start = ContinuousClock.now
        do {
            await YTService.shared.logout()
            let ver = try await YTService.shared.version(
                baseURL: settings.ytBaseURL,
                username: settings.ytUsername,
                password: settings.ytPassword
            )
            let ms = Int(start.duration(to: .now) / .milliseconds(1))
            return ("yt", .ok, ms, "yt-dlp \(ver)")
        } catch {
            return ("yt", .fail, nil, error.localizedDescription)
        }
    }

    private func probeSublink() async -> (String, ServiceHealthItem.Status, Int?, String) {
        let start = ContinuousClock.now
        do {
            _ = try await SublinkService.shared.fetchCaptcha(baseURL: settings.sublinkBaseURL)
            let ms = Int(start.duration(to: .now) / .milliseconds(1))
            return ("sublink", .ok, ms, "验证码接口可用")
        } catch {
            return ("sublink", .fail, nil, error.localizedDescription)
        }
    }

    private func probeKomari() async -> (String, ServiceHealthItem.Status, Int?, String) {
        let start = ContinuousClock.now
        do {
            let detail = try await KomariService.shared.probe(baseURL: settings.komariBaseURL)
            let ms = Int(start.duration(to: .now) / .milliseconds(1))
            return ("komari", .ok, ms, detail)
        } catch {
            return ("komari", .fail, nil, error.localizedDescription)
        }
    }

    private func probeCF() async -> (String, ServiceHealthItem.Status, Int?, String) {
        let start = ContinuousClock.now
        do {
            let cred = CFCredentials(settings: settings)
            let verify = try await CloudflareService.shared.verifyToken(cred: cred)
            let ms = Int(start.duration(to: .now) / .milliseconds(1))
            return ("cf", .ok, ms, verify.status)
        } catch {
            return ("cf", .fail, nil, error.localizedDescription)
        }
    }
}
