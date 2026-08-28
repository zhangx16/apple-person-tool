import Foundation
import UserNotifications

@MainActor final class ParcelStore: ObservableObject {
    static let shared = ParcelStore()
    @Published private(set) var parcels: [Parcel] = []
    @Published var isRefreshing = false
    @Published var message: String?
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("parcels.json")
        if let data = try? Data(contentsOf: fileURL), let value = try? JSONDecoder().decode([Parcel].self, from: data) { parcels = value }
    }
    var configured: Bool { !Secrets.get("customer").isEmpty && !Secrets.get("key").isEmpty }
    func add(number: String, alias: String, phone: String) {
        let clean = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty, !parcels.contains(where: { $0.number == clean }) else { return }
        let carrier = CarrierCatalog.guess(clean)
        parcels.insert(Parcel(id: UUID(), number: clean, carrierCode: carrier.0, carrierName: carrier.1, alias: alias, phoneTail: phone, state: nil, summary: configured ? "已添加，等待查询" : "请先在设置中配置查询密钥", events: [], createdAt: Date(), updatedAt: nil, isWatching: false), at: 0)
        save()
    }
    func delete(_ id: UUID) { parcels.removeAll { $0.id == id }; save() }
    func setWatching(_ id: UUID, _ value: Bool) {
        guard let index = parcels.firstIndex(where: { $0.id == id }) else { return }
        parcels[index].isWatching = value; save()
        if value { Task { try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) } }
    }
    func refresh(_ id: UUID) async {
        guard configured, let index = parcels.firstIndex(where: { $0.id == id }) else { message = "请先配置快递100 customer 和 key"; return }
        let oldEvent = parcels[index].events.first?.id
        isRefreshing = true; defer { isRefreshing = false }
        do {
            let client = Kuaidi100Client(customer: Secrets.get("customer"), key: Secrets.get("key"))
            let result = try await client.query(number: parcels[index].number, carrier: parcels[index].carrierCode, phone: parcels[index].phoneTail)
            parcels[index].state = result.0; parcels[index].events = result.1; parcels[index].carrierCode = result.2; parcels[index].carrierName = CarrierCatalog.name(result.2)
            parcels[index].summary = result.1.first?.description ?? "暂无物流轨迹"; parcels[index].updatedAt = Date()
            if parcels[index].isWatching, oldEvent != nil, oldEvent != result.1.first?.id { notify(parcels[index]) }
            message = "查询成功"; save()
        } catch { message = error.localizedDescription }
    }
    func refreshActive() async {
        for id in parcels.filter({ $0.bucket == .active }).map(\.id) { await refresh(id) }
    }
    private func save() { if let data = try? JSONEncoder().encode(parcels) { try? data.write(to: fileURL, options: .atomic) } }
    private func notify(_ parcel: Parcel) {
        let content = UNMutableNotificationContent(); content.title = "\(parcel.title) 有新物流"; content.body = parcel.summary; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "parcel.\(parcel.id)", content: content, trigger: nil))
    }
}
