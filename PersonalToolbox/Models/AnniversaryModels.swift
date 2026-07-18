import Foundation
import SwiftUI

// MARK: - Domain (aligned with iamwaa/Scripting 纪念日)

struct AnniversaryPerson: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var avatarFileName: String?
    var relationship: String?
    var notes: String
    var isPinned: Bool
    var createdAt: TimeInterval

    init(
        id: String = UUID().uuidString,
        name: String,
        avatarFileName: String? = nil,
        relationship: String? = nil,
        notes: String = "",
        isPinned: Bool = false,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.avatarFileName = avatarFileName
        self.relationship = relationship
        self.notes = notes
        self.isPinned = isPinned
        self.createdAt = createdAt
    }
}

enum AnniversaryEventType: String, Codable, CaseIterable, Identifiable, Sendable {
    case birthday
    case meet
    case love
    case wedding
    case enrollment
    case graduation
    case join
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .birthday: return "生日"
        case .meet: return "相识"
        case .love: return "恋爱"
        case .wedding: return "结婚"
        case .enrollment: return "入学"
        case .graduation: return "毕业"
        case .join: return "入职"
        case .custom: return "其他"
        }
    }

    var listLabel: String {
        switch self {
        case .birthday: return "生日"
        case .meet: return "相识纪念日"
        case .love: return "恋爱纪念日"
        case .wedding: return "结婚纪念日"
        case .enrollment: return "入学纪念日"
        case .graduation: return "毕业纪念日"
        case .join: return "入职纪念日"
        case .custom: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .birthday: return "gift.fill"
        case .meet: return "hand.wave.fill"
        case .love: return "heart.fill"
        case .wedding: return "heart.circle.fill"
        case .enrollment: return "book.fill"
        case .graduation: return "graduationcap.fill"
        case .join: return "briefcase.fill"
        case .custom: return "star.fill"
        }
    }

    var tint: Color {
        switch self {
        case .birthday: return Color(hex: 0xFF9500)
        case .meet: return Color(hex: 0x007AFF)
        case .love: return Color(hex: 0xFF2D55)
        case .wedding: return Color(hex: 0xAF52DE)
        case .enrollment: return Color(hex: 0x34C759)
        case .graduation: return Color(hex: 0x5856D6)
        case .join: return Color(hex: 0x5AC8FA)
        case .custom: return Color(hex: 0xFFCC00)
        }
    }
}

struct AnniversaryEvent: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var personId: String
    var title: String
    var type: AnniversaryEventType
    var isLunar: Bool
    /// yyyy-MM-dd local calendar baseline
    var gregorianDate: String
    var lunarYear: Int?
    var lunarMonth: Int?
    var lunarDay: Int?
    var isLeapMonth: Bool
    var reminderDays: [Int]
    var remindOnDay: Bool
    var repeatYearly: Bool
    var repeatMonthly: Bool
    var isPinned: Bool
    var showYearsAndDays: Bool
    var createdAt: TimeInterval

    init(
        id: String = UUID().uuidString,
        personId: String,
        title: String = "",
        type: AnniversaryEventType = .birthday,
        isLunar: Bool = false,
        gregorianDate: String,
        lunarYear: Int? = nil,
        lunarMonth: Int? = nil,
        lunarDay: Int? = nil,
        isLeapMonth: Bool = false,
        reminderDays: [Int] = [1, 3],
        remindOnDay: Bool = true,
        repeatYearly: Bool = true,
        repeatMonthly: Bool = false,
        isPinned: Bool = false,
        showYearsAndDays: Bool = false,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.personId = personId
        self.title = title
        self.type = type
        self.isLunar = isLunar
        self.gregorianDate = gregorianDate
        self.lunarYear = lunarYear
        self.lunarMonth = lunarMonth
        self.lunarDay = lunarDay
        self.isLeapMonth = isLeapMonth
        self.reminderDays = reminderDays
        self.remindOnDay = remindOnDay
        self.repeatYearly = repeatYearly
        self.repeatMonthly = repeatMonthly
        self.isPinned = isPinned
        self.showYearsAndDays = showYearsAndDays
        self.createdAt = createdAt
    }
}

struct AnniversaryAppSettings: Codable, Hashable, Sendable {
    var defaultReminderDays: [Int]
    var defaultRemindOnDay: Bool
    var notificationsEnabled: Bool
    var groupPastEvents: Bool
    var notificationHour: Int
    var notificationMinute: Int

    static let `default` = AnniversaryAppSettings(
        defaultReminderDays: [1, 3],
        defaultRemindOnDay: true,
        notificationsEnabled: true,
        groupPastEvents: true,
        notificationHour: 9,
        notificationMinute: 0
    )
}

struct AnniversaryAppData: Codable, Sendable {
    var persons: [AnniversaryPerson]
    var events: [AnniversaryEvent]
    var settings: AnniversaryAppSettings
    var version: Int

    static let empty = AnniversaryAppData(
        persons: [],
        events: [],
        settings: .default,
        version: 1
    )
}

struct AnniversaryOccurrence: Identifiable, Hashable {
    var id: String { event.id }
    var event: AnniversaryEvent
    var person: AnniversaryPerson
    var nextDate: Date
    var daysLeft: Int
    var age: Int?
    var months: Int?
    var daysSince: Int?
    var yearsPassed: Int?
}

enum AnniversaryRelationship {
    static let presets = ["自己", "伴侣", "子女", "家人", "朋友", "同学", "同事", "其他"]

    static func style(for name: String?) -> (systemImage: String, color: Color) {
        switch name {
        case "自己": return ("person.fill", Color(hex: 0x007AFF))
        case "伴侣": return ("heart.fill", Color(hex: 0xFF2D55))
        case "子女": return ("person.2.fill", Color(hex: 0xFF9500))
        case "家人": return ("house.fill", Color(hex: 0x34C759))
        case "朋友": return ("person.2.fill", Color(hex: 0x5856D6))
        case "同学": return ("graduationcap.fill", Color(hex: 0x5AC8FA))
        case "同事": return ("briefcase.fill", Color(hex: 0xAF52DE))
        default: return ("tag.fill", Color(hex: 0x8E8E93))
        }
    }

    static func allowedEventTypes(for relationship: String?) -> [AnniversaryEventType] {
        switch relationship {
        case "自己": return [.birthday, .enrollment, .graduation, .join]
        case "伴侣": return [.birthday, .meet, .love, .wedding]
        case "子女": return [.birthday, .enrollment, .graduation]
        case "家人": return [.birthday]
        case "朋友": return [.birthday, .meet]
        case "同学": return [.birthday, .meet, .graduation]
        case "同事": return [.birthday, .meet, .join]
        default: return [.birthday, .meet]
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
