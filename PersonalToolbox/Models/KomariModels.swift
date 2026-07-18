import Foundation

struct KomariEnvelope<T: Decodable>: Decodable {
    let data: T?
    let message: String?
    let status: String?
}

struct KomariNode: Decodable, Identifiable {
    var id: String { uuid }
    var uuid: String
    var name: String?
    var cpuName: String?
    var arch: String?
    var cpuCores: Int?
    var os: String?
    var region: String?
    var memTotal: Int64?
    var swapTotal: Int64?
    var diskTotal: Int64?
    var tags: String?
    var price: Double?
    var currency: String?
    var expiredAt: String?
    var trafficLimit: Int64?
    var updatedAt: String?
    var hidden: Bool?
    var weight: Int?

    enum CodingKeys: String, CodingKey {
        case uuid, name, arch, os, region, tags, price, currency, hidden, weight
        case cpuName = "cpu_name"
        case cpuCores = "cpu_cores"
        case memTotal = "mem_total"
        case swapTotal = "swap_total"
        case diskTotal = "disk_total"
        case expiredAt = "expired_at"
        case trafficLimit = "traffic_limit"
        case updatedAt = "updated_at"
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
    var uptime: Int64?
    var process: Int?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case uuid, cpu, ram, swap, disk, load, network, uptime, process
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

struct KomariNodeRow: Identifiable {
    var id: String { node.uuid }
    var node: KomariNode
    var recent: KomariRecentSample?
}
