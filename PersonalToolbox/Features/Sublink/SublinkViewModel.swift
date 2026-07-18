import Foundation
import Combine
import UIKit

@MainActor
final class SublinkViewModel: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case overview
        case nodes
        case subscriptions

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "概览"
            case .nodes: return "节点"
            case .subscriptions: return "订阅"
            }
        }
    }

    @Published var captchaImage: UIImage?
    @Published var captchaKey: String = ""
    @Published var captchaCode: String = ""
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var isMutating = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var dashboard: SublinkDashboard?
    @Published var nodes: [SublinkNode] = []
    @Published var subscriptions: [SublinkSub] = []
    @Published var groups: [String] = []
    @Published var pane: Pane = .overview
    @Published var nodeSearch: String = ""
    @Published var selectedGroupFilter: String? = nil

    private let service = SublinkService.shared

    var filteredNodes: [SublinkNode] {
        var list = nodes
        if let g = selectedGroupFilter, !g.isEmpty {
            list = list.filter { $0.groupNames.contains(g) }
        }
        let q = nodeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter {
                ($0.name ?? "").localizedCaseInsensitiveContains(q)
                    || ($0.link ?? "").localizedCaseInsensitiveContains(q)
                    || $0.groupNames.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            }
        }
        return list
    }

    // MARK: - Bootstrap / auth

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
            errorMessage = Self.errText(error)
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
            errorMessage = Self.errText(error)
            Haptics.error()
            await refreshCaptcha(settings: settings)
        }
    }

    func logout() {
        Task { await service.logout() }
        isLoggedIn = false
        dashboard = nil
        nodes = []
        subscriptions = []
        groups = []
        statusMessage = nil
        errorMessage = nil
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
            async let g = service.groups(baseURL: settings.sublinkBaseURL)
            dashboard = try await d
            nodes = try await n
            subscriptions = try await s
            groups = try await g
            // Keep filter valid
            if let f = selectedGroupFilter, !groups.contains(f) {
                selectedGroupFilter = nil
            }
        } catch NetworkError.unauthorized {
            isLoggedIn = false
            errorMessage = "会话已过期，请重新登录"
            await refreshCaptcha(settings: settings)
        } catch {
            errorMessage = Self.errText(error)
        }
    }

    // MARK: - Node mutations

    func addNode(
        settings: AppSettings,
        name: String,
        link: String,
        group: String
    ) async -> Bool {
        await mutate(settings: settings) {
            try await service.addNode(
                baseURL: settings.sublinkBaseURL,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                group: group.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            statusMessage = "节点已添加"
        }
    }

    func updateNode(
        settings: AppSettings,
        id: Int,
        name: String,
        link: String,
        group: String
    ) async -> Bool {
        await mutate(settings: settings) {
            try await service.updateNode(
                baseURL: settings.sublinkBaseURL,
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                group: group.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            statusMessage = "节点已更新"
        }
    }

    func deleteNode(settings: AppSettings, node: SublinkNode) async -> Bool {
        guard let id = node.nodeId else {
            errorMessage = "节点缺少 ID，无法删除"
            return false
        }
        return await mutate(settings: settings) {
            try await service.deleteNode(baseURL: settings.sublinkBaseURL, id: id)
            statusMessage = "已删除节点 \(node.displayName)"
        }
    }

    func bulkImportNodes(
        settings: AppSettings,
        rawText: String,
        group: String
    ) async -> Bool {
        let links = Self.splitLinks(rawText)
        guard !links.isEmpty else {
            errorMessage = "请粘贴至少一个节点链接"
            return false
        }
        return await mutate(settings: settings, refreshAfter: true) {
            let result = try await service.bulkAddNodes(
                baseURL: settings.sublinkBaseURL,
                links: links,
                group: group.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            var parts = ["新增 \(result.added)", "跳过 \(result.skipped)", "失败 \(result.failed)"]
            if let first = result.failures?.first {
                parts.append("例: \(first.error)")
            }
            statusMessage = parts.joined(separator: " · ")
        }
    }

    // MARK: - Subscription mutations

    func addSubscription(
        settings: AppSettings,
        name: String,
        nodeNames: [String],
        config: SublinkSubConfig
    ) async -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else {
            errorMessage = "订阅名称不能为空"
            return false
        }
        guard !nodeNames.isEmpty else {
            errorMessage = "请至少选择一个节点"
            return false
        }
        return await mutate(settings: settings) {
            try await service.addSubscription(
                baseURL: settings.sublinkBaseURL,
                name: n,
                nodeNames: nodeNames,
                config: config
            )
            statusMessage = "订阅已创建"
            pane = .subscriptions
        }
    }

    func updateSubscription(
        settings: AppSettings,
        oldName: String,
        name: String,
        nodeNames: [String],
        config: SublinkSubConfig
    ) async -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else {
            errorMessage = "订阅名称不能为空"
            return false
        }
        guard !nodeNames.isEmpty else {
            errorMessage = "请至少选择一个节点"
            return false
        }
        return await mutate(settings: settings) {
            try await service.updateSubscription(
                baseURL: settings.sublinkBaseURL,
                oldName: oldName,
                name: n,
                nodeNames: nodeNames,
                config: config
            )
            statusMessage = "订阅已更新"
        }
    }

    func deleteSubscription(settings: AppSettings, sub: SublinkSub) async -> Bool {
        guard let id = sub.subId else {
            errorMessage = "订阅缺少 ID，无法删除"
            return false
        }
        return await mutate(settings: settings) {
            try await service.deleteSubscription(baseURL: settings.sublinkBaseURL, id: id)
            statusMessage = "已删除订阅 \(sub.displayName)"
        }
    }

    // MARK: - Client URLs / clipboard

    func clientURL(settings: AppSettings, subscriptionName: String, client: SublinkClientKind = .auto) -> String {
        SublinkURLBuilder.clientURL(
            baseURL: settings.sublinkBaseURL,
            subscriptionName: subscriptionName,
            client: client
        )
    }

    func copyToPasteboard(_ text: String, label: String = "已复制") {
        UIPasteboard.general.string = text
        statusMessage = label
        Haptics.success()
    }

    // MARK: - Internals

    @discardableResult
    private func mutate(
        settings: AppSettings,
        refreshAfter: Bool = true,
        _ work: () async throws -> Void
    ) async -> Bool {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            try await work()
            Haptics.success()
            if refreshAfter {
                await refresh(settings: settings)
            }
            return true
        } catch NetworkError.unauthorized {
            isLoggedIn = false
            errorMessage = "会话已过期，请重新登录"
            Haptics.error()
            await refreshCaptcha(settings: settings)
            return false
        } catch {
            errorMessage = Self.errText(error)
            Haptics.error()
            return false
        }
    }

    private static func splitLinks(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func errText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
