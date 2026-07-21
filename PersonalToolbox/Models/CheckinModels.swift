import Foundation
import SwiftUI

// MARK: - Summary (GET /api/v1/summary)

struct CheckinSummary: Codable, Equatable {
    var ok: Bool?
    var generatedAt: String?
    var source: String?
    var counts: CheckinCounts?
    var providers: [CheckinProviderGroup]?
    /// Preferred: projects with accounts merged (same bot / same website provider).
    var projects: [CheckinProject]?
    /// Flat account-level items (compat / search fallback).
    var items: [CheckinItem]?
    var telegram: CheckinTelegramMeta?
    var embykeeper: CheckinEmbykeeperMeta?
    var auth: CheckinAuthMeta?
}

struct CheckinAuthMeta: Codable, Equatable {
    var appTokenConfigured: Bool?
}

struct CheckinCounts: Codable, Equatable {
    var total: Int?
    var projectTotal: Int?
    var success: Int?
    var already: Int?
    var failed: Int?
    var skipped: Int?
    var unknown: Int?
    var pending: Int?
    var healthy: Int?

    var totalValue: Int { total ?? 0 }
    var projectTotalValue: Int { projectTotal ?? 0 }
    var healthyValue: Int { healthy ?? ((success ?? 0) + (already ?? 0)) }
    var failedValue: Int { failed ?? 0 }
    var skippedValue: Int { skipped ?? 0 }
    var successValue: Int { success ?? 0 }
    var alreadyValue: Int { already ?? 0 }
}

struct CheckinProviderGroup: Codable, Equatable, Identifiable {
    var key: String?
    var label: String?
    var counts: CheckinCounts?
    var itemCount: Int?
    var projectCount: Int?
    var lastCheckedAt: String?

    var id: String { key ?? label ?? UUID().uuidString }
    var displayLabel: String { label ?? key ?? "未知" }
    var countValue: Int { projectCount ?? itemCount ?? 0 }
}

/// Merged check-in project (one TG bot or one website provider).
struct CheckinProject: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var kind: String?
    var provider: String?
    var providerLabel: String?
    var title: String?
    var subtitle: String?
    var botUsername: String?
    var botName: String?
    var avatarURL: String?
    var status: String?
    var ok: Bool?
    var message: String?
    var checkedAt: String?
    var accountCount: Int?
    var counts: CheckinCounts?
    var accounts: [CheckinItem]?

    var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        return providerLabel ?? provider ?? "签到项目"
    }

    var displaySubtitle: String {
        let s = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !s.isEmpty { return s }
        if let u = botUsername, !u.isEmpty { return "@\(u)" }
        return providerLabel ?? ""
    }

    var statusKind: CheckinStatusKind {
        CheckinStatusKind(rawValue: (status ?? "").lowercased()) ?? .unknown
    }

    var isTelegram: Bool { kind == "telegram_bot" || provider == "telegram_bot" }

    var accountList: [CheckinItem] { accounts ?? [] }

    var avatar: URL? {
        guard let raw = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }
}

struct CheckinItem: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var kind: String?
    var provider: String?
    var providerLabel: String?
    var accountName: String?
    var botName: String?
    var botUsername: String?
    var avatarURL: String?
    var phone: String?
    var status: String?
    var ok: Bool?
    var message: String?
    var checkedAt: String?
    var pointsDelta: Double?
    var balance: Double?
    var currency: String?
    var streak: Double?
    var leftDays: String?
    var todaySigned: Bool?
    var notes: String?

    var displayProvider: String { providerLabel ?? provider ?? "未知" }
    var displayName: String {
        let name = accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? displayProvider : name
    }

    var statusKind: CheckinStatusKind {
        CheckinStatusKind(rawValue: (status ?? "").lowercased()) ?? .unknown
    }

    var avatar: URL? {
        guard let raw = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }
}

enum CheckinStatusKind: String, CaseIterable {
    case success
    case already
    case failed
    case skipped
    case pending
    case unknown

    var title: String {
        switch self {
        case .success: return "成功"
        case .already: return "已签到"
        case .failed: return "失败"
        case .skipped: return "跳过"
        case .pending: return "未执行"
        case .unknown: return "未知"
        }
    }

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .already: return "checkmark.circle"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "forward.fill"
        case .pending: return "clock"
        case .unknown: return "questionmark.circle"
        }
    }

    var colorHex: UInt32 {
        switch self {
        case .success: return 0x30D158
        case .already: return 0x64D2FF
        case .failed: return 0xFF453A
        case .skipped: return 0xFF9F0A
        case .pending: return 0x8E8E93
        case .unknown: return 0x8E8E93
        }
    }

    var color: Color { Color(hex: colorHex) }
}

struct CheckinTelegramMeta: Codable, Equatable {
    var updatedAt: String?
    var botCount: Int?
}

struct CheckinEmbykeeperMeta: Codable, Equatable {
    var installed: Bool?
    var configPresent: Bool?
    var sessionFiles: Int?
    var sessionStringCount: Int?

    enum CodingKeys: String, CodingKey {
        case installed, configPresent, sessionFiles, sessionStringCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installed = try c.decodeIfPresent(Bool.self, forKey: .installed)
        configPresent = try c.decodeIfPresent(Bool.self, forKey: .configPresent)
        sessionStringCount = try c.decodeIfPresent(Int.self, forKey: .sessionStringCount)
        if let n = try? c.decodeIfPresent(Int.self, forKey: .sessionFiles) {
            sessionFiles = n
        } else if let arr = try? c.decodeIfPresent([String].self, forKey: .sessionFiles) {
            sessionFiles = arr.count
        } else {
            sessionFiles = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(installed, forKey: .installed)
        try c.encodeIfPresent(configPresent, forKey: .configPresent)
        try c.encodeIfPresent(sessionFiles, forKey: .sessionFiles)
        try c.encodeIfPresent(sessionStringCount, forKey: .sessionStringCount)
    }
}

struct CheckinHealth: Codable, Equatable {
    var ok: Bool?
    var now: String?
    var appTokenConfigured: Bool?
    var auth: String?
}
