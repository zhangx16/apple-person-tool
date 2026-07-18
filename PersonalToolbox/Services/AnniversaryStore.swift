import Foundation
import UIKit
import UserNotifications

/// Local persistence + notification scheduling for anniversaries.
@MainActor
final class AnniversaryStore: ObservableObject {
    static let shared = AnniversaryStore()

    @Published private(set) var persons: [AnniversaryPerson] = []
    @Published private(set) var events: [AnniversaryEvent] = []
    @Published private(set) var settings: AnniversaryAppSettings = .default
    @Published private(set) var isLoaded = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let dataFileName = "anniversary_data.json"
    private let avatarsFolderName = "AnniversaryAvatars"
    private let notificationPrefix = "anniversary.event."

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var dataURL: URL {
        documentsURL.appendingPathComponent(dataFileName)
    }

    private var avatarsDirURL: URL {
        documentsURL.appendingPathComponent(avatarsFolderName, isDirectory: true)
    }

    private init() {}

    // MARK: - Load / Save

    func load() {
        ensureAvatarsDir()
        defer { isLoaded = true }
        guard FileManager.default.fileExists(atPath: dataURL.path) else {
            persons = []
            events = []
            settings = .default
            return
        }
        do {
            let data = try Data(contentsOf: dataURL)
            let decoded = try JSONDecoder().decode(AnniversaryAppData.self, from: data)
            persons = decoded.persons
            events = decoded.events
            settings = decoded.settings
        } catch {
            persons = []
            events = []
            settings = .default
        }
        Task { await refreshAuthorizationStatus() }
        Task { await refreshNotifications() }
    }

    private func persist() {
        let payload = AnniversaryAppData(
            persons: persons,
            events: events,
            settings: settings,
            version: 1
        )
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: dataURL, options: [.atomic])
        } catch {
            // Best-effort local store; surface via UI later if needed.
        }
        Task { await refreshNotifications() }
    }

    private func ensureAvatarsDir() {
        try? FileManager.default.createDirectory(at: avatarsDirURL, withIntermediateDirectories: true)
    }

    // MARK: - Avatars

    func avatarURL(for fileName: String?) -> URL? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let url = avatarsDirURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func saveAvatarJPEG(_ image: UIImage, quality: CGFloat = 0.85) -> String? {
        ensureAvatarsDir()
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let name = "avatar_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).jpg"
        let url = avatarsDirURL.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic])
            return name
        } catch {
            return nil
        }
    }

    func deleteAvatarFile(_ fileName: String?) {
        guard let fileName, let url = avatarURL(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Mutations

    func upsertPerson(_ person: AnniversaryPerson) {
        if let idx = persons.firstIndex(where: { $0.id == person.id }) {
            persons[idx] = person
        } else {
            persons.append(person)
        }
        sortPersons()
        persist()
        Haptics.success()
    }

    func deletePerson(_ person: AnniversaryPerson) {
        events.removeAll { $0.personId == person.id }
        persons.removeAll { $0.id == person.id }
        deleteAvatarFile(person.avatarFileName)
        persist()
        Haptics.light()
    }

    func togglePinPerson(_ person: AnniversaryPerson) {
        guard let idx = persons.firstIndex(where: { $0.id == person.id }) else { return }
        persons[idx].isPinned.toggle()
        sortPersons()
        persist()
    }

    func upsertEvent(_ event: AnniversaryEvent) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx] = event
        } else {
            events.append(event)
        }
        persist()
        Haptics.success()
    }

    func deleteEvent(_ event: AnniversaryEvent) {
        events.removeAll { $0.id == event.id }
        persist()
        Haptics.light()
    }

    func togglePinEvent(_ event: AnniversaryEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].isPinned.toggle()
        persist()
    }

    func toggleCountdownFormat(_ event: AnniversaryEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].showYearsAndDays.toggle()
        persist()
    }

    func updateSettings(_ newSettings: AnniversaryAppSettings) {
        settings = newSettings
        persist()
    }

    func clearAll() {
        for p in persons {
            deleteAvatarFile(p.avatarFileName)
        }
        persons = []
        events = []
        persist()
    }

    private func sortPersons() {
        persons.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Derived

    var occurrences: [AnniversaryOccurrence] {
        AnniversaryDateUtils.buildOccurrenceList(events: events, persons: persons)
    }

    func person(id: String) -> AnniversaryPerson? {
        persons.first { $0.id == id }
    }

    func events(for personId: String) -> [AnniversaryEvent] {
        events.filter { $0.personId == personId }
    }

    // MARK: - Notifications

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestNotificationPermission() async -> Bool {
        do {
            let ok = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if ok { await refreshNotifications() }
            return ok
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func refreshNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix(notificationPrefix) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard settings.notificationsEnabled else { return }
        let status = await center.notificationSettings()
        guard status.authorizationStatus == .authorized || status.authorizationStatus == .provisional else {
            return
        }

        let now = Date()
        let rangeEnd = Calendar.current.date(byAdding: .day, value: 365, to: now) ?? now
        let hour = settings.notificationHour
        let minute = settings.notificationMinute

        for event in events {
            guard let person = person(id: event.personId) else { continue }
            var targets: [Date] = []
            if event.repeatMonthly || event.repeatYearly {
                // Walk occurrences within a year by probing monthly / yearly.
                if event.repeatMonthly, let first = AnniversaryDateUtils.nextOccurrence(of: event, from: now) {
                    var cursor = first
                    for _ in 0..<12 {
                        if cursor > rangeEnd { break }
                        targets.append(cursor)
                        guard let nextStart = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
                        guard let next = AnniversaryDateUtils.nextOccurrence(of: event, from: nextStart) else { break }
                        cursor = next
                    }
                } else if let first = AnniversaryDateUtils.nextOccurrence(of: event, from: now) {
                    targets.append(first)
                    if let year = Calendar.current.dateComponents([.year], from: first).year,
                       let nextYear = AnniversaryDateUtils.dateForYear(event, gregorianYear: year + 1),
                       nextYear <= rangeEnd {
                        targets.append(nextYear)
                    }
                }
            } else if let ref = AnniversaryDateUtils.referenceDate(of: event), ref >= AnniversaryDateUtils.startOfDay(now) {
                targets.append(ref)
            }

            var reminderOffsets = event.reminderDays.filter { $0 > 0 }
            if event.remindOnDay { reminderOffsets.append(0) }
            reminderOffsets = Array(Set(reminderOffsets)).sorted()

            for target in targets {
                for daysBefore in reminderOffsets {
                    guard let fireDay = Calendar.current.date(byAdding: .day, value: -daysBefore, to: target) else { continue }
                    var comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDay)
                    comps.hour = hour
                    comps.minute = minute
                    guard let fireDate = Calendar.current.date(from: comps), fireDate > now else { continue }

                    let content = UNMutableNotificationContent()
                    let pair = notificationCopy(event: event, person: person, daysBefore: daysBefore, target: target)
                    content.title = pair.title
                    content.body = pair.body
                    content.sound = .default

                    let triggerComps = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: fireDate
                    )
                    let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                    let id = "\(notificationPrefix)\(event.id).\(AnniversaryDateUtils.formatDateKey(target)).d\(daysBefore)"
                    let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                    try? await center.add(req)
                }
            }
        }
    }

    private func notificationCopy(
        event: AnniversaryEvent,
        person: AnniversaryPerson,
        daysBefore: Int,
        target: Date
    ) -> (title: String, body: String) {
        let name = person.name
        let label = AnniversaryDateUtils.effectiveType(of: event).listLabel
        let year = Calendar.current.component(.year, from: target)
        let years = AnniversaryDateUtils.yearsPassed(of: event, targetYear: year) ?? 0
        let suffix: String = {
            if years <= 0 { return "" }
            if AnniversaryDateUtils.effectiveType(of: event) == .birthday { return "\(years)岁" }
            return "第\(years)年"
        }()

        if daysBefore == 0 {
            let title = "今天是 \(name) 的\(label)"
            let body: String
            switch AnniversaryDateUtils.effectiveType(of: event) {
            case .birthday:
                body = suffix.isEmpty
                    ? "今天是\(name)的生日，去说声生日快乐吧"
                    : "\(name)今天\(suffix)了，去说声生日快乐吧"
            case .love, .wedding:
                if suffix.isEmpty {
                    body = "和\(name)的特别日子，今天好好庆祝一下"
                } else {
                    let num = suffix.replacingOccurrences(of: "第", with: "").replacingOccurrences(of: "年", with: "")
                    body = "不知不觉已经一起走过\(num)年了，今天好好庆祝一下"
                }
            default:
                body = "别忘了今天的\(label)"
            }
            return (title, body)
        }

        let timeHint = daysBefore == 1 ? "明天" : "\(daysBefore)天后"
        let title = "\(timeHint)是 \(name) 的\(label)"
        let body = "提前准备一下，别错过和\(name)的重要日子"
        return (title, body)
    }
}
