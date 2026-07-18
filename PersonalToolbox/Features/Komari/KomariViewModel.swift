import Foundation
import Combine

@MainActor
final class KomariViewModel: ObservableObject {
    @Published var rows: [KomariNodeRow] = []
    @Published var search = ""
    @Published var siteName: String?
    @Published var versionText: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var autoRefresh = true

    /// Detail cache
    @Published var detailHours: Int = 6
    @Published var loadRecords: [KomariLoadRecord] = []
    @Published var pingBasics: [KomariPingBasic] = []
    @Published var isDetailLoading = false
    @Published var detailError: String?

    private let service = KomariService.shared
    private var refreshTask: Task<Void, Never>?

    var filteredRows: [KomariNodeRow] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rows }
        return rows.filter {
            $0.node.displayName.localizedCaseInsensitiveContains(q)
                || ($0.node.region ?? "").localizedCaseInsensitiveContains(q)
                || ($0.node.tags ?? "").localizedCaseInsensitiveContains(q)
                || ($0.node.os ?? "").localizedCaseInsensitiveContains(q)
                || $0.node.uuid.localizedCaseInsensitiveContains(q)
        }
    }

    var onlineCount: Int { rows.filter(\.isOnline).count }

    func load(settings: AppSettings) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let dash = service.dashboard(baseURL: settings.komariBaseURL)
            async let pub = service.publicSettings(baseURL: settings.komariBaseURL)
            async let ver = service.version(baseURL: settings.komariBaseURL)

            rows = try await dash
            if let p = try? await pub {
                siteName = p.sitename
            }
            if let v = try? await ver {
                versionText = v.version
            }
            lastUpdated = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func startAutoRefresh(settings: AppSettings) {
        refreshTask?.cancel()
        guard autoRefresh else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled, self.autoRefresh else { break }
                await self.load(settings: settings)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func loadDetail(settings: AppSettings, uuid: String) async {
        isDetailLoading = true
        detailError = nil
        defer { isDetailLoading = false }
        do {
            async let load = service.loadRecords(
                baseURL: settings.komariBaseURL,
                uuid: uuid,
                hours: detailHours
            )
            async let ping = service.pingRecords(
                baseURL: settings.komariBaseURL,
                uuid: uuid,
                hours: detailHours
            )
            let loadBox = try await load
            let pingBox = try? await ping
            // Keep last ~40 points for sparkline
            let records = loadBox.records ?? []
            loadRecords = Array(records.suffix(40))
            pingBasics = pingBox?.basicInfo ?? []
        } catch {
            detailError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            loadRecords = []
            pingBasics = []
        }
    }
}
