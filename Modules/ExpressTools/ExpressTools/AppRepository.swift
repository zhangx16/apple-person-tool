import Foundation

@MainActor final class AppRepository: ObservableObject {
    static let shared = AppRepository()
    @Published var accounts: [BoundAccount] = [] { didSet { save(accounts, "accounts.json") } }
    @Published var addresses: [HomeAddress] = [] { didSet { save(addresses, "addresses.json") } }
    @Published var schedules: [ReportSchedule] = [] { didSet { save(schedules, "schedules.json") } }
    @Published var chat: [ExpressChatMessage] = [] { didSet { save(chat, "chat.json") } }
    @Published var pollingMinutes = 0 { didSet { UserDefaults.standard.set(pollingMinutes, forKey: "pollingMinutes") } }
    private let directory: URL

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        accounts = load("accounts.json", as: [BoundAccount].self) ?? []
        addresses = load("addresses.json", as: [HomeAddress].self) ?? []
        schedules = load("schedules.json", as: [ReportSchedule].self) ?? []
        chat = load("chat.json", as: [ExpressChatMessage].self) ?? []
        pollingMinutes = UserDefaults.standard.integer(forKey: "pollingMinutes")
    }
    func addAccount(source: DeliverySource, label: String, credential: String) {
        let key = "account.\(UUID().uuidString)"; Secrets.set(credential, for: key)
        accounts.append(BoundAccount(source: source, label: label.isEmpty ? source.title : label, secretKey: key))
    }
    func removeAccount(_ account: BoundAccount) { Secrets.set("", for: account.secretKey); accounts.removeAll { $0.id == account.id } }
    private func save<T: Encodable>(_ value: T, _ name: String) { if let data = try? JSONEncoder().encode(value) { try? data.write(to: directory.appendingPathComponent(name), options: .atomic) } }
    private func load<T: Decodable>(_ name: String, as: T.Type) -> T? { guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }; return try? JSONDecoder().decode(T.self, from: data) }
}
