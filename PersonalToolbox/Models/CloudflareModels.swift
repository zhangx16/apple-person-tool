import Foundation
import SwiftUI

// MARK: - Cloudflare API models (CFPanel-aligned MVP)

struct CFZone: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let status: String
    let paused: Bool
    let planName: String?
    let nameServers: [String]

    var statusColor: Color {
        switch status.lowercased() {
        case "active": return .green
        case "pending", "initializing", "moved": return .orange
        case "deactivated", "deleted": return .red
        default: return .secondary
        }
    }
}

struct CFDnsRecord: Identifiable, Hashable, Sendable {
    let id: String
    var type: String
    var name: String
    var content: String
    var ttl: Int
    var proxied: Bool
    var priority: Int?

    var ttlLabel: String {
        if ttl == 1 { return "自动" }
        if ttl < 60 { return "\(ttl)s" }
        if ttl < 3600 { return "\(ttl / 60)m" }
        return "\(ttl / 3600)h"
    }
}

struct CFDnsRecordInput: Sendable {
    var type: String
    var name: String
    var content: String
    var ttl: Int
    var proxied: Bool
    var priority: Int?
}

struct CFUsageSnapshot: Sendable {
    var workersRequests: Int
    var pagesRequests: Int
    var dailyLimit: Int
    var planName: String

    var totalRequests: Int { workersRequests + pagesRequests }

    var workersFraction: Double {
        guard dailyLimit > 0 else { return 0 }
        return min(1, Double(workersRequests) / Double(dailyLimit))
    }

    var pagesFraction: Double {
        guard dailyLimit > 0 else { return 0 }
        return min(1, Double(pagesRequests) / Double(dailyLimit))
    }

    var totalFraction: Double {
        guard dailyLimit > 0 else { return 0 }
        return min(1, Double(totalRequests) / Double(dailyLimit))
    }
}

struct CFAccountOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct CFTokenVerify: Sendable {
    var status: String
    var id: String?
}

enum CFDnsTypes {
    static let common = ["A", "AAAA", "CNAME", "TXT", "MX", "NS", "SRV", "CAA"]
}

enum CloudflareAccent {
    /// Match CFPanel script color rgba(243, 159, 68)
    static let color = Color(hex: 0xF39F44)
}
