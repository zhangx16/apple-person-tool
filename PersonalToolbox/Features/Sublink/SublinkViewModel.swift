import Foundation
import Combine
import UIKit

@MainActor
final class SublinkViewModel: ObservableObject {
    @Published var captchaImage: UIImage?
    @Published var captchaKey: String = ""
    @Published var captchaCode: String = ""
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var dashboard: SublinkDashboard?
    @Published var nodes: [SublinkNode] = []
    @Published var subscriptions: [SublinkSub] = []

    private let service = SublinkService.shared

    func bootstrap(settings: AppSettings) async {
        await service.restoreToken()
        if await service.hasToken {
            do {
                _ = try await service.overview(baseURL: settings.sublinkBaseURL)
                isLoggedIn = true
                await refresh(settings: settings)
                return
            } catch {
                await service.logout()
                isLoggedIn = false
            }
        }
        isLoggedIn = false
        await refreshCaptcha(settings: settings)
    }

    func refreshCaptcha(settings: AppSettings) async {
        errorMessage = nil
        do {
            let cap = try await service.fetchCaptcha(baseURL: settings.sublinkBaseURL)
            captchaKey = cap.captchaToken ?? ""
            captchaCode = ""
            captchaImage = Self.decodeDataURLImage(cap.imageDataURL)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func login(settings: AppSettings) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await service.login(
                baseURL: settings.sublinkBaseURL,
                username: settings.sublinkUsername,
                password: settings.sublinkPassword,
                captchaCode: captchaCode,
                captchaKey: captchaKey
            )
            isLoggedIn = true
            Haptics.success()
            await refresh(settings: settings)
        } catch {
            isLoggedIn = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Haptics.error()
            await refreshCaptcha(settings: settings)
        }
    }

    func logout() {
        Task {
            await service.logout()
        }
        isLoggedIn = false
        dashboard = nil
        nodes = []
        subscriptions = []
    }

    func refresh(settings: AppSettings) async {
        guard isLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let d = service.overview(baseURL: settings.sublinkBaseURL)
            async let n = service.nodes(baseURL: settings.sublinkBaseURL)
            async let s = service.subscriptions(baseURL: settings.sublinkBaseURL)
            dashboard = try await d
            nodes = try await n
            subscriptions = try await s
        } catch NetworkError.unauthorized {
            isLoggedIn = false
            errorMessage = "会话已过期，请重新登录"
            await refreshCaptcha(settings: settings)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func decodeDataURLImage(_ dataURL: String?) -> UIImage? {
        guard var s = dataURL, !s.isEmpty else { return nil }
        if let range = s.range(of: "base64,") {
            s = String(s[range.upperBound...])
        }
        guard let data = Data(base64Encoded: s) else { return nil }
        return UIImage(data: data)
    }
}
