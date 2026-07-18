import Foundation
import Combine

@MainActor
final class KomariViewModel: ObservableObject {
    @Published var rows: [KomariNodeRow] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private let service = KomariService.shared

    func load(settings: AppSettings) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            rows = try await service.dashboard(baseURL: settings.komariBaseURL)
            lastUpdated = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
