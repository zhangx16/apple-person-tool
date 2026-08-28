import Foundation

enum DeliverySource: String, CaseIterable, Codable, Identifiable {
    case xiaomi, jd, taobao, pdd, manual
    var id: String { rawValue }
    var title: String { switch self { case .xiaomi: "小米"; case .jd: "京东"; case .taobao: "淘宝 / 菜鸟"; case .pdd: "拼多多"; case .manual: "手动添加" } }
    var icon: String { switch self { case .xiaomi: "mi.square.fill"; case .jd: "bag.fill"; case .taobao: "basket.fill"; case .pdd: "cart.fill"; case .manual: "square.and.pencil" } }
}

struct BoundAccount: Codable, Identifiable, Hashable {
    var id = UUID()
    var source: DeliverySource
    var label: String
    var enabled = true
    /// Cookie/token 的 Keychain account key；敏感值不进入 JSON。
    var secretKey: String
}

struct HomeAddress: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    var address: String
}

struct ReportSchedule: Codable, Identifiable, Hashable {
    enum RepeatRule: String, CaseIterable, Codable { case once = "仅一次", daily = "每天", weekdays = "工作日", weekends = "周末" }
    var id = UUID()
    var hour = 8
    var minute = 30
    var rule = RepeatRule.daily
    var enabled = true
}

struct ExpressChatMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID(); var role: Role; var content: String; var date = Date()
}

struct ProviderParcel: Sendable {
    var number: String; var carrierCode: String; var carrierName: String; var title: String
    var state: String?; var summary: String; var source: DeliverySource; var accountLabel: String
}

protocol DeliveryProvider: Sendable {
    var source: DeliverySource { get }
    func synchronize(account: BoundAccount, credential: String) async throws -> [ProviderParcel]
    func timeline(for parcel: Parcel, account: BoundAccount, credential: String) async throws -> [TrackingEvent]
}
