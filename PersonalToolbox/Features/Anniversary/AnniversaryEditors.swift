import SwiftUI
import PhotosUI
import UserNotifications

// MARK: - Person editor

struct PersonEditorView: View {
    @ObservedObject var store: AnniversaryStore
    let person: AnniversaryPerson?
    var onSave: (AnniversaryPerson) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var relationship: String = "家人"
    @State private var customRelationship: String = ""
    @State private var notes: String = ""
    @State private var isPinned = false
    @State private var avatarFileName: String?
    @State private var avatarImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false

    private var isNew: Bool { person == nil }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let avatarImage {
                                Image(uiImage: avatarImage)
                                    .resizable()
                                    .scaledToFill()
                            } else if let url = store.avatarURL(for: avatarFileName),
                                      let ui = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ZStack {
                                    Circle().fill(Color(hex: 0xAE6DD8).opacity(0.18))
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 36))
                                        .foregroundStyle(Color(hex: 0xAE6DD8))
                                }
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Image(systemName: "camera.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color(hex: 0xAE6DD8))
                                .font(.system(size: 28))
                        }
                        .accessibilityLabel("选择头像")
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("基本信息") {
                TextField("姓名", text: $name)
                Picker("关系", selection: $relationship) {
                    ForEach(AnniversaryRelationship.presets, id: \.self) { r in
                        Text(r).tag(r)
                    }
                    Text("自定义").tag("__custom__")
                }
                if relationship == "__custom__" {
                    TextField("自定义关系", text: $customRelationship)
                }
                Toggle("置顶", isOn: $isPinned)
            }

            Section("备注") {
                TextField("备注（可选）", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if !isNew {
                Section {
                    Button("删除人物", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(isNew ? "新建人物" : "编辑人物")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
            }
        }
        .onAppear(perform: populate)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    avatarImage = ui
                }
            }
        }
        .confirmationDialog("删除此人物及其全部纪念日？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let person {
                    store.deletePerson(person)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func populate() {
        guard let person else { return }
        name = person.name
        if let rel = person.relationship, AnniversaryRelationship.presets.contains(rel) {
            relationship = rel
        } else if let rel = person.relationship, !rel.isEmpty {
            relationship = "__custom__"
            customRelationship = rel
        }
        notes = person.notes
        isPinned = person.isPinned
        avatarFileName = person.avatarFileName
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var fileName = avatarFileName
        if let avatarImage {
            if let old = avatarFileName { store.deleteAvatarFile(old) }
            fileName = store.saveAvatarJPEG(avatarImage)
        }
        let rel: String? = {
            if relationship == "__custom__" {
                let c = customRelationship.trimmingCharacters(in: .whitespacesAndNewlines)
                return c.isEmpty ? nil : c
            }
            return relationship
        }()
        let saved = AnniversaryPerson(
            id: person?.id ?? UUID().uuidString,
            name: trimmed,
            avatarFileName: fileName,
            relationship: rel,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isPinned: isPinned,
            createdAt: person?.createdAt ?? Date().timeIntervalSince1970
        )
        store.upsertPerson(saved)
        onSave(saved)
        dismiss()
    }
}

// MARK: - Event editor

struct EventEditorView: View {
    @ObservedObject var store: AnniversaryStore
    let person: AnniversaryPerson
    let event: AnniversaryEvent?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var type: AnniversaryEventType = .birthday
    @State private var isLunar = false
    @State private var gregorianDate = Date()
    @State private var repeatMode: RepeatMode = .yearly
    @State private var remindOnDay = true
    @State private var advanceEnabled = true
    @State private var advanceDays = 1
    @State private var isPinned = false
    @State private var showYearsAndDays = false
    @State private var showDeleteConfirm = false

    private enum RepeatMode: String, CaseIterable, Identifiable {
        case none = "不重复"
        case yearly = "每年"
        case monthly = "每月"
        var id: String { rawValue }
    }

    private var isNew: Bool { event == nil }

    private var typeOptions: [AnniversaryEventType] {
        var set = Set(AnniversaryRelationship.allowedEventTypes(for: person.relationship))
        set.insert(.custom)
        if let event { set.insert(event.type) }
        return AnniversaryEventType.allCases.filter { set.contains($0) }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AvatarView(
                        url: store.avatarURL(for: person.avatarFileName),
                        name: person.name,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.body.weight(.semibold))
                        if let rel = person.relationship {
                            Text(rel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("类型") {
                Picker("类型", selection: $type) {
                    ForEach(typeOptions) { t in
                        Label(t.label, systemImage: t.systemImage).tag(t)
                    }
                }
                if type == .custom {
                    TextField("标题", text: $title)
                }
            }

            Section("日期") {
                Toggle("农历", isOn: $isLunar)
                DatePicker(
                    isLunar ? "对应公历日期" : "日期",
                    selection: $gregorianDate,
                    displayedComponents: .date
                )
                .environment(\.locale, Locale(identifier: "zh_CN"))
                if isLunar {
                    let lunar = AnniversaryDateUtils.lunarParts(of: gregorianDate)
                    Text(AnniversaryDateUtils.formatLunar(month: lunar.month, day: lunar.day, isLeap: lunar.isLeapMonth))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("重复") {
                Picker("重复", selection: $repeatMode) {
                    ForEach(RepeatMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("提醒") {
                Toggle("当天提醒", isOn: $remindOnDay)
                Toggle("提前提醒", isOn: $advanceEnabled)
                if advanceEnabled {
                    Stepper("提前 \(advanceDays) 天", value: $advanceDays, in: 1...30)
                }
            }

            Section("其它") {
                Toggle("置顶", isOn: $isPinned)
                Toggle("倒计时显示年+天", isOn: $showYearsAndDays)
            }

            if !isNew {
                Section {
                    Button("删除纪念日", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(isNew ? "添加纪念日" : "编辑纪念日")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear(perform: populate)
        .confirmationDialog("确定删除该纪念日？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let event {
                    store.deleteEvent(event)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func populate() {
        guard let event else {
            let allowed = AnniversaryRelationship.allowedEventTypes(for: person.relationship)
            type = allowed.first ?? .birthday
            remindOnDay = store.settings.defaultRemindOnDay
            let days = store.settings.defaultReminderDays
            if let first = days.first, first > 0 {
                advanceEnabled = true
                advanceDays = first
            } else {
                advanceEnabled = false
            }
            return
        }
        title = event.title
        type = event.type
        isLunar = event.isLunar
        gregorianDate = AnniversaryDateUtils.parseDateKey(event.gregorianDate) ?? Date()
        if event.repeatMonthly {
            repeatMode = .monthly
        } else if event.repeatYearly {
            repeatMode = .yearly
        } else {
            repeatMode = .none
        }
        remindOnDay = event.remindOnDay
        if let first = event.reminderDays.first(where: { $0 > 0 }) {
            advanceEnabled = true
            advanceDays = first
        } else {
            advanceEnabled = false
            advanceDays = 1
        }
        isPinned = event.isPinned
        showYearsAndDays = event.showYearsAndDays
    }

    private func save() {
        let lunar = AnniversaryDateUtils.lunarParts(of: gregorianDate)
        var reminderDays: [Int] = []
        if advanceEnabled {
            reminderDays = [advanceDays]
        }
        let saved = AnniversaryEvent(
            id: event?.id ?? UUID().uuidString,
            personId: person.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            isLunar: isLunar,
            gregorianDate: AnniversaryDateUtils.formatDateKey(gregorianDate),
            lunarYear: isLunar ? lunar.year : nil,
            lunarMonth: isLunar ? lunar.month : nil,
            lunarDay: isLunar ? lunar.day : nil,
            isLeapMonth: isLunar ? lunar.isLeapMonth : false,
            reminderDays: reminderDays,
            remindOnDay: remindOnDay,
            repeatYearly: repeatMode == .yearly,
            repeatMonthly: repeatMode == .monthly,
            isPinned: isPinned,
            showYearsAndDays: showYearsAndDays,
            createdAt: event?.createdAt ?? Date().timeIntervalSince1970
        )
        store.upsertEvent(saved)
        dismiss()
    }
}

// MARK: - Settings

struct AnniversarySettingsView: View {
    @ObservedObject var store: AnniversaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ServiceBrandIcon(brand: .anniversary, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("纪念日")
                            .font(.headline)
                        Text("本地记录重要日子与提醒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("通知") {
                Toggle("启用本地通知", isOn: Binding(
                    get: { store.settings.notificationsEnabled },
                    set: { v in
                        var s = store.settings
                        s.notificationsEnabled = v
                        store.updateSettings(s)
                        if v {
                            Task { await store.requestNotificationPermission() }
                        }
                    }
                ))
                Stepper(
                    "提醒时间 \(String(format: "%02d:%02d", store.settings.notificationHour, store.settings.notificationMinute))",
                    value: Binding(
                        get: { store.settings.notificationHour * 60 + store.settings.notificationMinute },
                        set: { total in
                            var s = store.settings
                            s.notificationHour = min(23, max(0, total / 60))
                            s.notificationMinute = min(59, max(0, total % 60))
                            store.updateSettings(s)
                        }
                    ),
                    in: 0...(23 * 60 + 59),
                    step: 15
                )
                Button("请求通知权限") {
                    Task { await store.requestNotificationPermission() }
                }
                Text(authStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("默认提醒") {
                Toggle("默认当天提醒", isOn: Binding(
                    get: { store.settings.defaultRemindOnDay },
                    set: { v in
                        var s = store.settings
                        s.defaultRemindOnDay = v
                        store.updateSettings(s)
                    }
                ))
                Stepper(
                    "默认提前 \(store.settings.defaultReminderDays.first ?? 1) 天",
                    value: Binding(
                        get: { store.settings.defaultReminderDays.first ?? 1 },
                        set: { v in
                            var s = store.settings
                            s.defaultReminderDays = [max(1, min(30, v))]
                            store.updateSettings(s)
                        }
                    ),
                    in: 1...30
                )
            }

            Section("列表") {
                Toggle("将已过纪念日单独分组", isOn: Binding(
                    get: { store.settings.groupPastEvents },
                    set: { v in
                        var s = store.settings
                        s.groupPastEvents = v
                        store.updateSettings(s)
                    }
                ))
            }

            Section {
                Button("清空全部数据", role: .destructive) {
                    showClearConfirm = true
                }
            } footer: {
                Text("数据仅保存在本机，不会上传。清空后无法恢复。")
            }
        }
        .navigationTitle("纪念日设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .confirmationDialog("确定清空全部人物与纪念日？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                store.clearAll()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            await store.refreshAuthorizationStatus()
        }
    }

    private var authStatusText: String {
        switch store.authorizationStatus {
        case .authorized: return "通知权限：已授权"
        case .provisional: return "通知权限：临时授权"
        case .denied: return "通知权限：已拒绝（请到系统设置开启）"
        case .notDetermined: return "通知权限：尚未请求"
        case .ephemeral: return "通知权限：临时"
        @unknown default: return "通知权限：未知"
        }
    }
}
