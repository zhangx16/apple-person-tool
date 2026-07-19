import Foundation

/// Recently opened tools in 服务 hub.
@MainActor
final class LiveRecentStore: ObservableObject {
    static let shared = LiveRecentStore()

    /// Service brand raw values, newest first.
    @Published private(set) var recentBrands: [String] = []

    private let key = "servicesHub.recentBrands.v1"
    private let maxCount = 8

    private init() {
        recentBrands = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func record(_ brand: ServiceBrand) {
        var list = recentBrands.filter { $0 != brand.rawValue }
        list.insert(brand.rawValue, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        recentBrands = list
        UserDefaults.standard.set(list, forKey: key)
    }

    func brands() -> [ServiceBrand] {
        recentBrands.compactMap { ServiceBrand(rawValue: $0) }
    }
}
