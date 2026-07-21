import Foundation

/// Lightweight SSH host bookmarks.
/// Full interactive terminal is intentionally not re-implemented — recommend
/// [Blink Shell](https://github.com/blinksh/blink) / [Citadel](https://github.com/orlandos-nl/Citadel)
/// for embedding later; this module stores hosts + opens Next Terminal / SSH URL schemes.
struct SSHHost: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var host: String
    var port: Int
    var username: String
    var notes: String
    var createdAt: Date

    var sshURL: URL? {
        // openssh / termius style; many apps register ssh://
        var c = URLComponents()
        c.scheme = "ssh"
        c.host = host
        c.port = port == 22 ? nil : port
        c.user = username.isEmpty ? nil : username
        return c.url
    }
}

@MainActor
final class SSHHostStore: ObservableObject {
    static let shared = SSHHostStore()
    private let fileName = "ssh_hosts.json"

    @Published private(set) var hosts: [SSHHost] = []

    private init() {
        hosts = LocalJSONStore.load([SSHHost].self, from: fileName, fallback: [])
    }

    private func persist() {
        LocalJSONStore.save(hosts, to: fileName)
    }

    func upsert(_ host: SSHHost) {
        if let i = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[i] = host
        } else {
            hosts.insert(host, at: 0)
        }
        persist()
    }

    func delete(id: String) {
        hosts.removeAll { $0.id == id }
        persist()
    }
}
