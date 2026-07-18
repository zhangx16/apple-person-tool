import Foundation

/// Gregorian / Chinese lunar helpers for anniversary calculations.
enum AnniversaryDateUtils {
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private static var chinese: Calendar {
        var c = Calendar(identifier: .chinese)
        c.timeZone = .current
        return c
    }

    static let lunarMonthNames = [
        "", "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    static let lunarDayNames = [
        "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    // MARK: - Formatting

    static func formatDateKey(_ date: Date) -> String {
        dayKeyFormatter.string(from: startOfDay(date))
    }

    static func parseDateKey(_ value: String) -> Date? {
        dayKeyFormatter.date(from: value).map(startOfDay)
    }

    static func formatDateCN(_ date: Date) -> String {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日"
    }

    static func formatLunar(month: Int, day: Int, isLeap: Bool) -> String {
        let m = lunarMonthNames.indices.contains(month) ? lunarMonthNames[month] : "\(month)月"
        let d = lunarDayNames.indices.contains(day) ? lunarDayNames[day] : "\(day)"
        return "农历\(isLeap ? "闰" : "")\(m)\(d)"
    }

    static func startOfDay(_ date: Date) -> Date {
        gregorian.startOfDay(for: date)
    }

    static func localDate(year: Int, month: Int, day: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return gregorian.date(from: comps).map(startOfDay)
    }

    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let a = startOfDay(from)
        let b = startOfDay(to)
        return gregorian.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Lunar

    struct LunarParts: Equatable {
        var year: Int
        var month: Int
        var day: Int
        var isLeapMonth: Bool
    }

    static func lunarParts(of date: Date) -> LunarParts {
        let comps = chinese.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        // Chinese calendar year is cyclic; use era+year when available for display anchoring.
        let year = comps.year ?? 0
        return LunarParts(
            year: year,
            month: comps.month ?? 0,
            day: comps.day ?? 0,
            isLeapMonth: comps.isLeapMonth ?? false
        )
    }

    /// Find gregorian date in `gregorianYear` matching lunar month/day.
    static func findGregorianDateForLunar(
        lunarMonth: Int,
        lunarDay: Int,
        isLeapMonth: Bool,
        gregorianYear: Int
    ) -> Date? {
        guard let start = localDate(year: gregorianYear, month: 1, day: 1),
              let end = localDate(year: gregorianYear + 1, month: 1, day: 1) else { return nil }
        var lastMatch: Date?
        var cursor = start
        while cursor < end {
            let p = lunarParts(of: cursor)
            if p.month == lunarMonth && p.day == lunarDay && p.isLeapMonth == isLeapMonth {
                lastMatch = cursor
            }
            guard let next = gregorian.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        if lastMatch != nil { return lastMatch }
        if isLeapMonth {
            return findGregorianDateForLunar(
                lunarMonth: lunarMonth,
                lunarDay: lunarDay,
                isLeapMonth: false,
                gregorianYear: gregorianYear
            )
        }
        return nil
    }

    // MARK: - Effective type

    static func effectiveType(of event: AnniversaryEvent) -> AnniversaryEventType {
        if event.type != .custom { return event.type }
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.contains("生日") { return .birthday }
        if title.contains("恋爱") { return .love }
        if title.contains("结婚") || title.contains("婚礼") { return .wedding }
        return .custom
    }

    // MARK: - Occurrence

    static func referenceDate(of event: AnniversaryEvent) -> Date? {
        parseDateKey(event.gregorianDate)
    }

    static func dateForYear(_ event: AnniversaryEvent, gregorianYear: Int) -> Date? {
        if !event.repeatYearly {
            return referenceDate(of: event)
        }
        if event.isLunar, let m = event.lunarMonth, let d = event.lunarDay {
            return findGregorianDateForLunar(
                lunarMonth: m,
                lunarDay: d,
                isLeapMonth: event.isLeapMonth,
                gregorianYear: gregorianYear
            )
        }
        guard let ref = referenceDate(of: event) else { return nil }
        let comps = gregorian.dateComponents([.month, .day], from: ref)
        return localDate(year: gregorianYear, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    static func nextOccurrence(of event: AnniversaryEvent, from: Date = Date()) -> Date? {
        guard let ref = referenceDate(of: event) else { return nil }
        let today = startOfDay(from)
        let refLocal = startOfDay(ref)

        if event.repeatMonthly {
            let day = gregorian.component(.day, from: ref)
            let refMonth = gregorian.component(.month, from: refLocal) - 1
            let refYear = gregorian.component(.year, from: refLocal)
            let fromMonth = gregorian.component(.month, from: from) - 1
            let fromYear = gregorian.component(.year, from: from)
            var startMonth: Int
            var startYear: Int
            if fromYear > refYear || (fromYear == refYear && fromMonth >= refMonth) {
                startMonth = fromMonth
                startYear = fromYear
            } else {
                startMonth = refMonth
                startYear = refYear
            }
            for offset in 0..<12 {
                var month = startMonth + offset
                var year = startYear
                if month >= 12 {
                    year += month / 12
                    month = month % 12
                }
                let maxDay = gregorian.range(of: .day, in: .month, for: localDate(year: year, month: month + 1, day: 1) ?? today)?.count ?? 28
                let actualDay = min(day, maxDay)
                guard let candidate = localDate(year: year, month: month + 1, day: actualDay) else { continue }
                if candidate >= today && candidate >= refLocal {
                    return candidate
                }
            }
            return nil
        }

        if !event.repeatYearly && !event.repeatMonthly {
            return refLocal
        }

        let startYear = max(gregorian.component(.year, from: from), gregorian.component(.year, from: refLocal))
        for offset in 0...1 {
            guard let date = dateForYear(event, gregorianYear: startYear + offset) else { continue }
            let candidate = startOfDay(date)
            if candidate >= today && candidate >= refLocal {
                return candidate
            }
        }
        return nil
    }

    static func age(of event: AnniversaryEvent, today: Date = Date()) -> Int? {
        guard effectiveType(of: event) == .birthday, let ref = referenceDate(of: event) else { return nil }
        let birthYear = gregorian.component(.year, from: ref)
        let thisYear = gregorian.component(.year, from: today)
        var birthdayThisYear: Date?
        if event.isLunar, let m = event.lunarMonth, let d = event.lunarDay {
            birthdayThisYear = findGregorianDateForLunar(
                lunarMonth: m, lunarDay: d, isLeapMonth: event.isLeapMonth, gregorianYear: thisYear
            )
        } else {
            let comps = gregorian.dateComponents([.month, .day], from: ref)
            birthdayThisYear = localDate(year: thisYear, month: comps.month ?? 1, day: comps.day ?? 1)
        }
        var age = thisYear - birthYear
        if let b = birthdayThisYear, today < b {
            age -= 1
        }
        return max(0, age)
    }

    static func yearsPassed(of event: AnniversaryEvent, targetYear: Int, from: Date = Date()) -> Int? {
        guard let ref = referenceDate(of: event) else { return nil }
        let baseYear = gregorian.component(.year, from: ref)
        var yearsDiff = targetYear - baseYear
        if event.isLunar, let m = event.lunarMonth, let d = event.lunarDay,
           let lunarDate = findGregorianDateForLunar(
            lunarMonth: m, lunarDay: d, isLeapMonth: event.isLeapMonth, gregorianYear: targetYear
           ) {
            let isPast = from >= lunarDate
            return max(0, isPast ? yearsDiff : yearsDiff - 1)
        }
        let comps = gregorian.dateComponents([.month, .day], from: ref)
        guard let anniversary = localDate(year: targetYear, month: comps.month ?? 1, day: comps.day ?? 1) else {
            return max(0, yearsDiff)
        }
        let isPast = from >= anniversary
        return max(0, isPast ? yearsDiff : yearsDiff - 1)
    }

    static func monthsSince(event: AnniversaryEvent, today: Date = Date()) -> Int? {
        guard var referenceDate = referenceDate(of: event) else { return nil }
        if event.isLunar, let m = event.lunarMonth, let d = event.lunarDay,
           let lunar = findGregorianDateForLunar(
            lunarMonth: m, lunarDay: d, isLeapMonth: event.isLeapMonth,
            gregorianYear: gregorian.component(.year, from: today)
           ) {
            referenceDate = lunar
        }
        var months = (gregorian.component(.year, from: today) - gregorian.component(.year, from: referenceDate)) * 12
            + (gregorian.component(.month, from: today) - gregorian.component(.month, from: referenceDate))
        if gregorian.component(.day, from: today) < gregorian.component(.day, from: referenceDate) {
            months -= 1
        }
        return max(0, months)
    }

    static func weddingAnniversaryName(years: Int) -> String? {
        if years >= 80 { return "钻石婚" }
        if years >= 70 { return "白金婚" }
        if years >= 60 { return "钻石婚" }
        if years >= 55 { return "绿宝石婚" }
        if years >= 50 { return "金婚" }
        if years >= 45 { return "蓝宝石婚" }
        if years >= 40 { return "红宝石婚" }
        if years >= 35 { return "珊瑚婚" }
        if years >= 30 { return "珍珠婚" }
        if years >= 25 { return "银婚" }
        if years >= 20 { return "瓷婚" }
        if years >= 15 { return "水晶婚" }
        let map: [Int: String] = [
            1: "纸婚", 2: "棉婚", 3: "皮婚", 4: "花果婚", 5: "木婚",
            6: "糖婚", 7: "手婚", 8: "古铜婚", 9: "陶器婚", 10: "锡婚",
            11: "钢婚", 12: "丝婚", 13: "花边婚", 14: "象牙婚"
        ]
        return map[years]
    }

    static func formatElapsedYearsAndDays(from: Date, to: Date) -> String {
        let fromLocal = startOfDay(from)
        let toLocal = startOfDay(to)
        var years = gregorian.component(.year, from: toLocal) - gregorian.component(.year, from: fromLocal)
        let anchorComps = gregorian.dateComponents([.month, .day], from: fromLocal)
        if let anchor = localDate(
            year: gregorian.component(.year, from: fromLocal) + years,
            month: anchorComps.month ?? 1,
            day: anchorComps.day ?? 1
        ), anchor > toLocal {
            years -= 1
        }
        let start = localDate(
            year: gregorian.component(.year, from: fromLocal) + years,
            month: anchorComps.month ?? 1,
            day: anchorComps.day ?? 1
        ) ?? fromLocal
        let days = daysBetween(start, toLocal)
        if years <= 0 { return "\(days) 天" }
        if days == 0 { return "\(years) 年" }
        return "\(years) 年 \(days) 天"
    }

    static func buildOccurrenceList(
        events: [AnniversaryEvent],
        persons: [AnniversaryPerson],
        from: Date = Date()
    ) -> [AnniversaryOccurrence] {
        let personMap = Dictionary(uniqueKeysWithValues: persons.map { ($0.id, $0) })
        var result: [AnniversaryOccurrence] = []
        let year = gregorian.component(.year, from: from)
        for event in events {
            guard let person = personMap[event.personId] else { continue }
            let displayDate: Date?
            if event.repeatYearly || event.repeatMonthly {
                displayDate = nextOccurrence(of: event, from: from) ?? referenceDate(of: event)
            } else {
                displayDate = referenceDate(of: event)
            }
            guard let next = displayDate else { continue }
            let ageVal = age(of: event, today: from)
            let effective = effectiveType(of: event)
            let isLoveOrWedding = effective == .love || effective == .wedding
            let years = isLoveOrWedding ? yearsPassed(of: event, targetYear: year, from: from) : nil
            let needsMonths = (ageVal == 0) || (isLoveOrWedding && years == 0)
            let months = needsMonths ? monthsSince(event: event, today: from) : nil
            let daysSince: Int? = {
                guard months == 0, let ref = referenceDate(of: event) else { return nil }
                return daysBetween(ref, from)
            }()
            result.append(
                AnniversaryOccurrence(
                    event: event,
                    person: person,
                    nextDate: next,
                    daysLeft: daysBetween(from, next),
                    age: ageVal,
                    months: months,
                    daysSince: daysSince,
                    yearsPassed: years
                )
            )
        }
        return result.sorted { $0.daysLeft < $1.daysLeft }
    }
}
