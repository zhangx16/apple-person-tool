import SwiftUI
import UIKit

// MARK: - Reminders

struct ReminderHomeView: View {
    @StateObject private var store = ReminderStore.shared
    @State private var showAdd = false

    var body: some View {
        List {
            if store.items.isEmpty {
                ContentUnavailableView("暂无提醒", systemImage: "bell", description: Text("添加续费日、账单日、待办截止等。"))
            } else {
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title).font(.headline)
                            Spacer()
                            Text(item.daysLeft >= 0 ? "\(item.daysLeft) 天" : "已过期")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.daysLeft <= 3 ? Color.red : .secondary)
                        }
                        Text(item.dueAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !item.notes.isEmpty {
                            Text(item.notes).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.delete(id: item.id) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("提醒")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            ReminderEditorSheet { showAdd = false }
        }
        .task { _ = await LocalNotifier.ensureAuthorized() }
    }
}

private struct ReminderEditorSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var due = Date().addingTimeInterval(86400)
    @State private var notify = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                TextField("备注", text: $notes)
                DatePicker("时间", selection: $due)
                Toggle("到期通知", isOn: $notify)
            }
            .navigationTitle("新建提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let item = AppReminder(
                            id: UUID().uuidString,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: notes,
                            dueAt: due,
                            notify: notify,
                            createdAt: Date()
                        )
                        guard !item.title.isEmpty else { return }
                        ReminderStore.shared.upsert(item)
                        ActivityEventStore.shared.log(.make(
                            title: "添加提醒",
                            subtitle: item.title,
                            systemImage: "bell.fill",
                            tintHex: 0xFF9F0A,
                            route: "reminder"
                        ))
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Subscriptions

struct SubscriptionHomeView: View {
    @StateObject private var store = SubscriptionStore.shared
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                LabeledContent("月度估算", value: String(format: "¥%.2f", store.monthTotal))
                LabeledContent("条目", value: "\(store.items.count)")
            }
            Section("列表") {
                if store.items.isEmpty {
                    Text("记录 VPS / 流媒体 / API 账单").foregroundStyle(.secondary)
                }
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name).font(.headline)
                            Spacer()
                            Text(String(format: "%.2f %@", item.amount, item.currency))
                                .font(.subheadline.monospacedDigit())
                        }
                        Text("\(item.cycleTitle) · 下次 \(item.nextDue.formatted(date: .abbreviated, time: .omitted)) · \(item.daysUntilDue) 天")
                            .font(.caption)
                            .foregroundStyle(item.daysUntilDue <= 7 ? Color.orange : .secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.delete(id: item.id) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("订阅账单")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            SubscriptionEditorSheet { showAdd = false }
        }
    }
}

private struct SubscriptionEditorSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var currency = "CNY"
    @State private var cycle = "monthly"
    @State private var nextDue = Date().addingTimeInterval(86400 * 30)
    @State private var notes = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                TextField("金额", text: $amount)
                    .keyboardType(.decimalPad)
                TextField("币种", text: $currency)
                Picker("周期", selection: $cycle) {
                    Text("月付").tag("monthly")
                    Text("年付").tag("yearly")
                    Text("一次性").tag("once")
                }
                DatePicker("下次扣费", selection: $nextDue, displayedComponents: .date)
                TextField("官网 / 面板", text: $url)
                TextField("备注", text: $notes)
            }
            .navigationTitle("添加订阅")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let a = Double(amount) ?? 0
                        let item = SubscriptionItem(
                            id: UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            amount: a,
                            currency: currency,
                            cycle: cycle,
                            nextDue: nextDue,
                            notes: notes,
                            url: url,
                            createdAt: Date()
                        )
                        guard !item.name.isEmpty else { return }
                        SubscriptionStore.shared.upsert(item)
                        ActivityEventStore.shared.log(.make(
                            title: "添加订阅",
                            subtitle: item.name,
                            systemImage: "creditcard.fill",
                            tintHex: 0x34C759,
                            route: "subscription"
                        ))
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Certificate watch

struct CertMonitorHomeView: View {
    @StateObject private var store = CertExpiryStore.shared
    @State private var host = ""
    @State private var notAfter = Date().addingTimeInterval(86400 * 90)
    @State private var useManualDate = true

    var body: some View {
        List {
            Section("添加域名") {
                TextField("host（如 checkin.031216.xyz）", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("手动填写到期日", isOn: $useManualDate)
                if useManualDate {
                    DatePicker("证书到期", selection: $notAfter, displayedComponents: .date)
                }
                Button("添加") {
                    store.add(
                        host: host,
                        note: "",
                        notAfter: useManualDate ? notAfter : nil
                    )
                    host = ""
                }
            }
            Section {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    if store.isChecking {
                        ProgressView()
                    } else {
                        Label("探测 HTTPS 连通", systemImage: "network")
                    }
                }
            }
            Section("监视列表") {
                if store.items.isEmpty {
                    Text("用于域名 / TLS 到期提醒").foregroundStyle(.secondary)
                }
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.host).font(.headline)
                        if let d = item.daysLeft {
                            Text("剩余 \(d) 天 · \(item.notAfter?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                                .font(.caption)
                                .foregroundStyle(d <= 14 ? Color.red : .secondary)
                        } else {
                            Text("未设置到期日 · 可编辑笔记")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let err = item.error {
                            Text(err).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.delete(id: item.id) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("证书到期")
    }
}

// MARK: - Fast Note Sync

struct FastNoteHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var notes: [FastNoteSyncService.NoteListItem] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var selectedPath: String?
    @State private var noteBody = ""

    var body: some View {
        Group {
            if !settings.isFastNoteConfigured {
                ContentUnavailableView(
                    "配置笔记同步",
                    systemImage: "note.text",
                    description: Text("设置 Base URL、账号密码后登录。服务端为 Fast Note Sync（可与 Obsidian 插件共用）。")
                )
            } else {
                List {
                    if let errorText {
                        Text(errorText).foregroundStyle(.red).font(.caption)
                    }
                    Section("笔记") {
                        if isLoading && notes.isEmpty {
                            ProgressView("加载…")
                        }
                        ForEach(notes) { n in
                            Button {
                                selectedPath = n.path
                                Task { await openNote(n.path ?? "") }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.displayTitle).foregroundStyle(.primary)
                                    if let p = n.path {
                                        Text(p).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .refreshable { await reload() }
            }
        }
        .navigationTitle("笔记同步")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loginAndReload() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        .sheet(item: Binding(
            get: { selectedPath.map { NotePathBox(id: $0) } },
            set: { selectedPath = $0?.id }
        )) { box in
            NavigationStack {
                TextEditor(text: $noteBody)
                    .padding()
                    .navigationTitle((box.id as NSString).lastPathComponent)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { selectedPath = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                Task { await saveNote(path: box.id) }
                            }
                        }
                    }
            }
        }
        .task { await loginAndReload() }
    }

    private struct NotePathBox: Identifiable {
        var id: String
    }

    private func loginAndReload() async {
        guard settings.isFastNoteConfigured else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            if settings.fastNoteToken.isEmpty {
                let token = try await FastNoteSyncService.shared.login(
                    baseURL: settings.fastNoteBaseURL,
                    username: settings.fastNoteUsername,
                    password: settings.fastNotePassword
                )
                await MainActor.run { settings.fastNoteToken = token }
            }
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func reload() async {
        guard !settings.fastNoteToken.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            notes = try await FastNoteSyncService.shared.listNotes(
                baseURL: settings.fastNoteBaseURL,
                token: settings.fastNoteToken
            )
        } catch {
            // token expired → re-login once
            do {
                let token = try await FastNoteSyncService.shared.login(
                    baseURL: settings.fastNoteBaseURL,
                    username: settings.fastNoteUsername,
                    password: settings.fastNotePassword
                )
                await MainActor.run { settings.fastNoteToken = token }
                notes = try await FastNoteSyncService.shared.listNotes(
                    baseURL: settings.fastNoteBaseURL,
                    token: token
                )
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func openNote(_ path: String) async {
        guard !path.isEmpty else { return }
        do {
            noteBody = try await FastNoteSyncService.shared.getNote(
                baseURL: settings.fastNoteBaseURL,
                token: settings.fastNoteToken,
                path: path
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveNote(path: String) async {
        do {
            try await FastNoteSyncService.shared.saveNote(
                baseURL: settings.fastNoteBaseURL,
                token: settings.fastNoteToken,
                path: path,
                content: noteBody
            )
            Haptics.success()
            selectedPath = nil
            ActivityEventStore.shared.log(.make(
                title: "笔记已保存",
                subtitle: path,
                systemImage: "note.text",
                tintHex: 0xBF5AF2,
                route: "notes"
            ))
        } catch {
            errorText = error.localizedDescription
            Haptics.error()
        }
    }
}

// MARK: - SSH hosts

struct SSHHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var store = SSHHostStore.shared
    @State private var showAdd = false
    @State private var showWeb = false

    var body: some View {
        List {
            Section {
                Text("完整交互终端推荐开源项目：Blink Shell、Citadel（SwiftNIO SSH）。本模块提供主机书签 + 可选打开 Next Terminal Web 面板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !settings.nextTerminalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Web 终端") {
                    Button {
                        showWeb = true
                    } label: {
                        Label("打开 Next Terminal", systemImage: "terminal")
                    }
                }
            }
            Section("主机") {
                if store.hosts.isEmpty {
                    Text("添加常用 SSH 主机").foregroundStyle(.secondary)
                }
                ForEach(store.hosts) { h in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.name).font(.headline)
                        Text("\(h.username)@\(h.host):\(h.port)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.delete(id: h.id) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        if let url = h.sshURL {
                            Link("用系统/第三方打开 ssh://", destination: url)
                        }
                    }
                }
            }
        }
        .navigationTitle("SSH")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            SSHEditorSheet { showAdd = false }
        }
        .sheet(isPresented: $showWeb) {
            if let url = URL(string: settings.nextTerminalURL) {
                NavigationStack {
                    WebPortalView(url: url, title: "Next Terminal")
                }
            }
        }
    }
}

private struct SSHEditorSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = "root"
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                TextField("主机", text: $host)
                    .textInputAutocapitalization(.never)
                TextField("端口", text: $port)
                    .keyboardType(.numberPad)
                TextField("用户", text: $username)
                    .textInputAutocapitalization(.never)
                TextField("备注", text: $notes)
            }
            .navigationTitle("添加主机")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let item = SSHHost(
                            id: UUID().uuidString,
                            name: name.isEmpty ? host : name,
                            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                            port: Int(port) ?? 22,
                            username: username,
                            notes: notes,
                            createdAt: Date()
                        )
                        guard !item.host.isEmpty else { return }
                        SSHHostStore.shared.upsert(item)
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Simple in-app Safari-like portal for self-hosted web UIs.
struct WebPortalView: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Reuse system browser for reliability (cookie/login).
        // In-app WKWebView can be added later if needed.
        VStack(spacing: 16) {
            Text("将在系统浏览器中打开：")
                .font(.subheadline)
            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                UIApplication.shared.open(url)
            } label: {
                Label("打开", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .onAppear {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Backup / restore settings blob

struct BackupExportView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var exportText = ""
    @State private var importText = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section("导出（不含密钥明文时可自检）") {
                Button("生成配置快照") {
                    exportText = SettingsBackup.exportJSON(settings: settings)
                }
                if !exportText.isEmpty {
                    Text(exportText)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(12)
                    Button("复制") {
                        UIPasteboard.general.string = exportText
                        Haptics.success()
                    }
                }
            }
            Section("导入") {
                TextField("粘贴 JSON", text: $importText, axis: .vertical)
                    .lineLimit(4...10)
                Button("应用非敏感字段") {
                    message = SettingsBackup.importSafeFields(json: importText, settings: settings)
                }
            }
            if let message {
                Section { Text(message).font(.caption) }
            }
        }
        .navigationTitle("备份导出")
    }
}

enum SettingsBackup {
    static func exportJSON(settings: AppSettings) -> String {
        let dict: [String: Any] = [
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "sub2apiBaseURL": settings.sub2apiBaseURL,
            "ytBaseURL": settings.ytBaseURL,
            "sublinkBaseURL": settings.sublinkBaseURL,
            "komariBaseURL": settings.komariBaseURL,
            "checkinBaseURL": settings.checkinBaseURL,
            "clsFeedURL": settings.clsFeedURL,
            "fastNoteBaseURL": settings.fastNoteBaseURL,
            "nextTerminalURL": settings.nextTerminalURL,
            "note": "Secrets (API keys/passwords) are NOT included."
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    static func importSafeFields(json: String, settings: AppSettings) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "JSON 无效"
        }
        if let v = obj["sub2apiBaseURL"] as? String { settings.sub2apiBaseURL = v }
        if let v = obj["ytBaseURL"] as? String { settings.ytBaseURL = v }
        if let v = obj["sublinkBaseURL"] as? String { settings.sublinkBaseURL = v }
        if let v = obj["komariBaseURL"] as? String { settings.komariBaseURL = v }
        if let v = obj["checkinBaseURL"] as? String { settings.checkinBaseURL = v }
        if let v = obj["clsFeedURL"] as? String { settings.clsFeedURL = v }
        if let v = obj["fastNoteBaseURL"] as? String { settings.fastNoteBaseURL = v }
        if let v = obj["nextTerminalURL"] as? String { settings.nextTerminalURL = v }
        return "已导入 URL 类配置（密钥仍需手动填写）"
    }
}
