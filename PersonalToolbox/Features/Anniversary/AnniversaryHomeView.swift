import SwiftUI
import PhotosUI

/// 纪念日主界面：倒计时列表 + 人物管理（参考 iamwaa/Scripting「纪念日」）。
struct AnniversaryHomeView: View {
    @ObservedObject private var store = AnniversaryStore.shared
    @State private var segment: Segment = .events
    @State private var showAddEventPicker = false
    @State private var showNewPerson = false
    @State private var editingPerson: AnniversaryPerson?
    @State private var editingEvent: AnniversaryEvent?
    @State private var eventPerson: AnniversaryPerson?
    @State private var detailPerson: AnniversaryPerson?
    @State private var showSettings = false
    @State private var personForNewEvent: AnniversaryPerson?

    private enum Segment: String, CaseIterable, Identifiable {
        case events = "纪念日"
        case people = "人物"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("分段", selection: $segment) {
                ForEach(Segment.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch segment {
                case .events:
                    eventsList
                case .people:
                    peopleList
                }
            }
        }
        .background(AppSurfaceBackground(accent: Color.accentColor))
        .navigationTitle("纪念日")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .anniversary, title: "纪念日")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddEventPicker = true
                    } label: {
                        Label("添加纪念日", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        showNewPerson = true
                    } label: {
                        Label("添加人物", systemImage: "person.badge.plus")
                    }
                    Divider()
                    Button {
                        showSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color(hex: 0xAE6DD8))
                }
                .accessibilityLabel("添加")
            }
        }
        .onAppear {
            if !store.isLoaded { store.load() }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                AnniversarySettingsView(store: store)
            }
        }
        .sheet(isPresented: $showNewPerson) {
            NavigationStack {
                PersonEditorView(store: store, person: nil) { _ in }
            }
        }
        .sheet(item: $editingPerson) { person in
            NavigationStack {
                PersonEditorView(store: store, person: person) { _ in }
            }
        }
        .sheet(isPresented: $showAddEventPicker) {
            NavigationStack {
                PersonPickerSheet(
                    persons: store.persons,
                    onSelect: { person in
                        showAddEventPicker = false
                        personForNewEvent = person
                    },
                    onCreatePerson: {
                        showAddEventPicker = false
                        showNewPerson = true
                    }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $personForNewEvent) { person in
            NavigationStack {
                EventEditorView(store: store, person: person, event: nil)
            }
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                EventEditorView(
                    store: store,
                    person: store.person(id: event.personId) ?? AnniversaryPerson(name: "未知"),
                    event: event
                )
            }
        }
        .navigationDestination(item: $detailPerson) { person in
            PersonDetailView(store: store, personId: person.id)
        }
    }

    // MARK: - Events

    private var eventsList: some View {
        let items = store.occurrences
        let pinned = items.filter { $0.event.isPinned }
        let unpinned = items.filter { !$0.event.isPinned }
        let upcoming = store.settings.groupPastEvents ? unpinned.filter { $0.daysLeft >= 0 } : unpinned
        let past = store.settings.groupPastEvents ? unpinned.filter { $0.daysLeft < 0 } : []

        return Group {
            if items.isEmpty {
                emptyState(
                    title: "还没有纪念日",
                    systemImage: "heart.text.square",
                    message: "添加人物后记录生日、恋爱或其它重要日子"
                ) {
                    showAddEventPicker = true
                }
            } else {
                List {
                    if !pinned.isEmpty {
                        Section("置顶") {
                            ForEach(pinned) { item in
                                eventRow(item)
                            }
                        }
                    }
                    ForEach(groupedByMonth(upcoming), id: \.key) { group in
                        Section(group.title) {
                            ForEach(group.items) { item in
                                eventRow(item)
                            }
                        }
                    }
                    if !past.isEmpty {
                        Section("已过") {
                            ForEach(past.sorted { $0.nextDate > $1.nextDate }) { item in
                                eventRow(item)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func eventRow(_ item: AnniversaryOccurrence) -> some View {
        Button {
            editingEvent = item.event
        } label: {
            AnniversaryEventRow(item: item, avatarURL: store.avatarURL(for: item.person.avatarFileName))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.deleteEvent(item.event)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                store.togglePinEvent(item.event)
            } label: {
                Label(item.event.isPinned ? "取消置顶" : "置顶", systemImage: item.event.isPinned ? "pin.slash" : "pin")
            }
            .tint(Color(hex: 0xAE6DD8))
        }
        .contextMenu {
            Button {
                store.togglePinEvent(item.event)
            } label: {
                Label(item.event.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
            }
            Button {
                store.toggleCountdownFormat(item.event)
            } label: {
                Label("切换年+天显示", systemImage: "textformat.123")
            }
            Button(role: .destructive) {
                store.deleteEvent(item.event)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - People

    private var peopleList: some View {
        Group {
            if store.persons.isEmpty {
                emptyState(
                    title: "还没有人物",
                    systemImage: "person.2",
                    message: "先添加家人、伴侣或朋友"
                ) {
                    showNewPerson = true
                }
            } else {
                List {
                    ForEach(store.persons) { person in
                        Button {
                            detailPerson = person
                        } label: {
                            PersonRowView(person: person, avatarURL: store.avatarURL(for: person.avatarFileName))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.deletePerson(person)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.togglePinPerson(person)
                            } label: {
                                Label(person.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
                            }
                            .tint(Color(hex: 0xAE6DD8))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Helpers

    private struct MonthGroup {
        var key: String
        var title: String
        var items: [AnniversaryOccurrence]
    }

    private func groupedByMonth(_ items: [AnniversaryOccurrence]) -> [MonthGroup] {
        let cal = Calendar.current
        var dict: [String: [AnniversaryOccurrence]] = [:]
        for item in items {
            let y = cal.component(.year, from: item.nextDate)
            let m = cal.component(.month, from: item.nextDate)
            let key = String(format: "%04d-%02d", y, m)
            dict[key, default: []].append(item)
        }
        return dict.keys.sorted().map { key in
            let parts = key.split(separator: "-")
            let title = "\(parts[0])年\(Int(parts[1]) ?? 0)月"
            return MonthGroup(key: key, title: title, items: dict[key] ?? [])
        }
    }

    private func emptyState(title: String, systemImage: String, message: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(hex: 0xAE6DD8).opacity(0.85))
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: action) {
                Text("开始添加")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0xAE6DD8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Rows

struct AnniversaryEventRow: View {
    let item: AnniversaryOccurrence
    let avatarURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: avatarURL, name: item.person.name, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.person.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if item.event.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: 0xAE6DD8))
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: item.event.type.systemImage)
                        .font(.caption)
                        .foregroundStyle(item.event.type.tint)
                    Text(displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(dateLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(daysLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(daysColor)
                Text(metaLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.person.name)，\(displayTitle)，\(daysLabel)，\(metaLabel)")
    }

    private var displayTitle: String {
        let t = item.event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? item.event.type.listLabel : t
    }

    private var dateLine: String {
        var parts = [AnniversaryDateUtils.formatDateCN(item.nextDate)]
        if item.event.isLunar, let m = item.event.lunarMonth, let d = item.event.lunarDay {
            parts.append(AnniversaryDateUtils.formatLunar(month: m, day: d, isLeap: item.event.isLeapMonth))
        }
        return parts.joined(separator: " · ")
    }

    private var daysLabel: String {
        if item.daysLeft == 0 { return "今天" }
        if item.daysLeft > 0 { return "\(item.daysLeft)天" }
        return "已过\(-item.daysLeft)天"
    }

    private var daysColor: Color {
        if item.daysLeft == 0 { return Color(hex: 0xFF2D55) }
        if item.daysLeft > 0 && item.daysLeft <= 7 { return Color(hex: 0xFF9500) }
        if item.daysLeft < 0 { return .secondary }
        return Color(hex: 0xAE6DD8)
    }

    private var metaLabel: String {
        if let age = item.age {
            if age == 0, let months = item.months {
                if months == 0, let d = item.daysSince { return "\(d)天" }
                return "\(months)个月"
            }
            return "\(age)岁"
        }
        if let y = item.yearsPassed {
            if y == 0, let months = item.months {
                if months == 0, let d = item.daysSince { return "\(d)天" }
                return "\(months)个月"
            }
            if item.event.showYearsAndDays, let ref = AnniversaryDateUtils.referenceDate(of: item.event) {
                return AnniversaryDateUtils.formatElapsedYearsAndDays(from: ref, to: Date())
            }
            if let name = AnniversaryDateUtils.weddingAnniversaryName(years: y),
               AnniversaryDateUtils.effectiveType(of: item.event) == .wedding {
                return "\(y)年 · \(name)"
            }
            return "\(y)周年"
        }
        return item.event.type.label
    }
}

struct PersonRowView: View {
    let person: AnniversaryPerson
    let avatarURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: avatarURL, name: person.name, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if person.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: 0xAE6DD8))
                    }
                }
                if let rel = person.relationship, !rel.isEmpty {
                    let style = AnniversaryRelationship.style(for: rel)
                    Label(rel, systemImage: style.systemImage)
                        .font(.caption)
                        .foregroundStyle(style.color)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xAE6DD8).opacity(0.18))
            if let url, let ui = UIImage(contentsOfFile: url.path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xAE6DD8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var initials: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "?" : String(t.prefix(1))
    }
}

// MARK: - Person detail

struct PersonDetailView: View {
    @ObservedObject var store: AnniversaryStore
    let personId: String
    @State private var editingPerson: AnniversaryPerson?
    @State private var editingEvent: AnniversaryEvent?
    @State private var addingEvent = false

    private var person: AnniversaryPerson? {
        store.person(id: personId)
    }

    var body: some View {
        Group {
            if let person {
                List {
                    Section {
                        HStack(spacing: 14) {
                            AvatarView(
                                url: store.avatarURL(for: person.avatarFileName),
                                name: person.name,
                                size: 64
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                Text(person.name)
                                    .font(.title3.weight(.semibold))
                                if let rel = person.relationship, !rel.isEmpty {
                                    let style = AnniversaryRelationship.style(for: rel)
                                    Label(rel, systemImage: style.systemImage)
                                        .font(.subheadline)
                                        .foregroundStyle(style.color)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        if !person.notes.isEmpty {
                            Text(person.notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("纪念日") {
                        let list = store.events(for: personId)
                        if list.isEmpty {
                            Text("暂无纪念日")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(list) { event in
                                Button {
                                    editingEvent = event
                                } label: {
                                    HStack {
                                        Image(systemName: event.type.systemImage)
                                            .foregroundStyle(event.type.tint)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.title.isEmpty ? event.type.listLabel : event.title)
                                                .foregroundStyle(.primary)
                                            Text(event.gregorianDate)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .onDelete { idx in
                                for i in idx {
                                    store.deleteEvent(list[i])
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppSurfaceBackground(accent: Color.accentColor))
                .navigationTitle(person.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("编辑人物") { editingPerson = person }
                            Button("添加纪念日") { addingEvent = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(item: $editingPerson) { p in
                    NavigationStack {
                        PersonEditorView(store: store, person: p) { _ in }
                    }
                }
                .sheet(isPresented: $addingEvent) {
                    NavigationStack {
                        EventEditorView(store: store, person: person, event: nil)
                    }
                }
                .sheet(item: $editingEvent) { event in
                    NavigationStack {
                        EventEditorView(store: store, person: person, event: event)
                    }
                }
            } else {
                ContentUnavailableView("人物不存在", systemImage: "person.slash")
            }
        }
    }
}

// MARK: - Person picker

struct PersonPickerSheet: View {
    let persons: [AnniversaryPerson]
    var onSelect: (AnniversaryPerson) -> Void
    var onCreatePerson: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    onCreatePerson()
                } label: {
                    Label("新建人物", systemImage: "person.badge.plus")
                }
            }
            Section("选择人物") {
                if persons.isEmpty {
                    Text("暂无人物，请先新建")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(persons) { person in
                        Button {
                            onSelect(person)
                        } label: {
                            Text(person.name)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle("选择人物")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }
}
