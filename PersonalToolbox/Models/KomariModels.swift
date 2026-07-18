import Foundation

struct KomariEnvelope<T: Decodable>: Decodable {
    let data: T?
    let message: String?
    let status: String?
}

struct KomariVersion: Decodable {
    var version: String?
    var hash: String?
}

struct KomariPublicSettings: Decodable {
    var sitename: String?
    var description: String?
    var privateSite: Bool?
    var recordEnabled: Bool?
    var recordPreserveTime: Int?
    var pingRecordPreserveTime: Int?
    var theme: String?

    enum CodingKeys: String, CodingKey {
        case sitename, description, theme
        case privateSite = "private_site"
        case recordEnabled = "record_enabled"
        case recordPreserveTime = "record_preserve_time"
        case pingRecordPreserveTime = "ping_record_preserve_time"
    }
}

struct KomariNode: Decodable, Identifiable, Hashable {
    var id: String { uuid }
    var uuid: String
    var name: String?
    var cpuName: String?
    var arch: String?
    var cpuCores: Int?
    var os: String?
    var kernelVersion: String?
    var region: String?
    var memTotal: Int64?
    var swapTotal: Int64?
    var diskTotal: Int64?
    var tags: String?
    var group: String?
    var price: Double?
    var currency: String?
    var expiredAt: String?
    var trafficLimit: Int64?
    var trafficLimitType: String?
    var updatedAt: String?
    var hidden: Bool?
    var weight: Int?
    var virtualization: String?

    enum CodingKeys: String, CodingKey {
        case uuid, name, arch, os, region, tags, price, currency, hidden, weight, group, virtualization
        case cpuName = "cpu_name"
        case cpuCores = "cpu_cores"
        case memTotal = "mem_total"
        case swapTotal = "swap_total"
        case diskTotal = "disk_total"
        case expiredAt = "expired_at"
        case trafficLimit = "traffic_limit"
        case trafficLimitType = "traffic_limit_type"
        case updatedAt = "updated_at"
        case kernelVersion = "kernel_version"
    }

    var displayName: String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? uuid : n
    }
}

struct KomariRecentSample: Decodable {
    var uuid: String?
    var cpu: KomariUsage?
    var ram: KomariMem?
    var swap: KomariMem?
    var disk: KomariMem?
    var load: KomariLoad?
    var network: KomariNet?
    var connections: KomariConnections?
    var uptime: Int64?
    var process: Int?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case uuid, cpu, ram, swap, disk, load, network, connections, uptime, process
        case updatedAt = "updated_at"
    }
}

struct KomariUsage: Decodable {
    var usage: Double?
}

struct KomariMem: Decodable {
    var total: Int64?
    var used: Int64?

    var usedPercent: Double {
        guard let total, total > 0, let used else { return 0 }
        return Double(used) / Double(total) * 100
    }
}

struct KomariLoad: Decodable {
    var load1: Double?
    var load5: Double?
    var load15: Double?
}

struct KomariNet: Decodable {
    var up: Int64?
    var down: Int64?
    var totalUp: Int64?
    var totalDown: Int64?
}

struct KomariConnections: Decodable {
    var tcp: Int?
    var udp: Int?
}

struct KomariLoadRecordsBox: Decodable {
    var count: Int?
    var hasGpuData: Bool?
    var records: [KomariLoadRecord]?

    enum CodingKeys: String, CodingKey {
        case count, records
        case hasGpuData = "has_gpu_data"
    }
}

struct KomariLoadRecord: Decodable, Identifiable {
    var id: String { "\(time ?? "")-\(cpu ?? 0)-\(ram ?? 0)" }
    var client: String?
    var time: String?
    var cpu: Double?
    var ram: Int64?
    var ramTotal: Int64?
    var disk: Int64?
    var diskTotal: Int64?
    var netIn: Int64?
    var netOut: Int64?
    var netTotalUp: Int64?
    var netTotalDown: Int64?
    var load: Double?
    var process: Int?
    var connections: Int?

    enum CodingKeys: String, CodingKey {
        case client, time, cpu, ram, disk, load, process, connections
        case ramTotal = "ram_total"
        case diskTotal = "disk_total"
        case netIn = "net_in"
        case netOut = "net_out"
        case netTotalUp = "net_total_up"
        case netTotalDown = "net_total_down"
    }

    var ramPercent: Double {
        guard let ramTotal, ramTotal > 0, let ram else { return 0 }
        return Double(ram) / Double(ramTotal) * 100
    }
}

struct KomariPingRecordsBox: Decodable {
    var count: Int?
    var basicInfo: [KomariPingBasic]?
    var records: [KomariPingRecord]?

    enum CodingKeys: String, CodingKey {
        case count, records
        case basicInfo = "basic_info"
    }
}

struct KomariPingBasic: Decodable, Identifiable {
    var id: String { "\(client ?? "")-\(min ?? 0)-\(max ?? 0)" }
    var client: String?
    var loss: Double?
    var min: Double?
    var max: Double?
}

struct KomariPingRecord: Decodable, Identifiable {
    var id: String { "\(taskId ?? 0)-\(time ?? "")-\(value ?? 0)" }
    var taskId: Int?
    var time: String?
    var value: Double?
    var client: String?

    enum CodingKeys: String, CodingKey {
        case time, value, client
        case taskId = "task_id"
    }
}

struct KomariPingTask: Decodable, Identifiable {
    var id: Int
    var name: String?
    var clients: [String]?
}

struct KomariNodeRow: Identifiable, Hashable {
    var id: String { node.uuid }
    var node: KomariNode
    var recent: KomariRecentSample?

    /// Treat as online if recent sample exists and updated within ~3 minutes when parseable.
    var isOnline: Bool {
        guard let recent else { return false }
        guard let updated = recent.updatedAt, let date = KomariTime.parse(updated) else {
            return true
        }
        return Date().timeIntervalSince(date) < 180
    }

    var cpuUsage: Double { recent?.cpu?.usage ?? 0 }

    static func == (lhs: KomariNodeRow, rhs: KomariNodeRow) -> Bool {
        lhs.node.uuid == rhs.node.uuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(node.uuid)
    }
}

enum KomariTime {
    static func parse(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        // Fallback: strip fractional nanos if over-precise
        if let t = raw.split(separator: ".").first {
            let s = String(t) + "Z"
            return iso.date(from: s.replacingOccurrences(of: "ZZ", with: "Z"))
        }
        return nil
    }
}
