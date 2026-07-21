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
    /// Preset shell commands (copy / show). Full remote exec needs Citadel/Blink.
    var presets: [SSHPreset]
    var createdAt: Date

    var sshURL: URL? {
        var c = URLComponents()
        c.scheme = "ssh"
        c.host = host
        c.port = port == 22 ? nil : port
        c.user = username.isEmpty ? nil : username
        return c.url
    }

    func cli(for preset: SSHPreset? = nil) -> String {
        let base = "ssh -p \(port) \(username)@\(host)"
        guard let preset, !preset.command.isEmpty else { return base }
        let escaped = preset.command.replacingOccurrences(of: "'", with: "'\\''")
        return "\(base) '\(escaped)'"
    }
}

struct SSHPreset: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var command: String
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
        var h = host
        if h.presets.isEmpty {
            h.presets = Self.defaultPresets
        }
        if let i = hosts.firstIndex(where: { $0.id == h.id }) {
            hosts[i] = h
        } else {
            hosts.insert(h, at: 0)
        }
        persist()
    }

    static let defaultPresets: [SSHPreset] = [
        .init(id: "df", title: "磁盘", command: "df -h"),
        .init(id: "free", title: "内存", command: "free -h || vm_stat"),
        .init(id: "docker", title: "容器", command: "docker ps --format 'table {{.Names}}\t{{.Status}}'"),
        .init(id: "uptime", title: "负载", command: "uptime")
    ]

    func delete(id: String) {
        hosts.removeAll { $0.id == id }
        persist()
    }
}
