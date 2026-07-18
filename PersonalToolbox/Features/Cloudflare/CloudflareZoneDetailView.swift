import SwiftUI

struct CloudflareZoneDetailView: View {
    @EnvironmentObject private var settings: AppSettings
    let zone: CFZone

    @State private var records: [CFDnsRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPurgeConfirm = false
    @State private var isPurging = false
    @State private var toast: String?
    @State private var editing: CFDnsRecord?
    @State private var showAdd = false
    @State private var search = ""

    private let service = CloudflareService.shared
    private let accent = CloudflareAccent.color

    var body: some View {
        List {
            Section("域名") {
                LabeledContent("状态") {
                    Text(zone.status).foregroundStyle(zone.statusColor)
                }
                if let plan = zone.planName {
                    LabeledContent("套餐", value: plan)
                }
                if !zone.nameServers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name Servers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(zone.nameServers, id: \.self) { ns in
                            Text(ns)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showPurgeConfirm = true
                } label: {
                    if isPurging {
                        ProgressView()
                    } else {
                        Label("清除全部缓存", systemImage: "trash")
                    }
                }
                .disabled(isPurging)
            } footer: {
                Text("等同 Cloudflare「Purge Everything」，会影响该域名全部缓存。")
            }

            Section {
                if isLoading && records.isEmpty {
                    HStack {
                        ProgressView()
                        Text("加载 DNS…")
                            .foregroundStyle(.secondary)
                    }
                } else if filteredRecords.isEmpty {
                    Text(search.isEmpty ? "暂无 DNS 记录" : "无匹配记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredRecords) { record in
                        Button {
                            editing = record
                        } label: {
                            dnsRow(record)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await deleteRecord(record) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("DNS（\(filteredRecords.count)）")
                    Spacer()
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppleTheme.canvas)
        .navigationTitle(zone.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "筛选 DNS")
        .refreshable { await loadDNS() }
        .task { await loadDNS() }
        .confirmationDialog("清除 \(zone.name) 的全部缓存？", isPresented: $showPurgeConfirm, titleVisibility: .visible) {
            Button("清除全部", role: .destructive) {
                Task { await purge() }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                CFDnsEditorView(zone: zone, record: nil) {
                    Task { await loadDNS() }
                }
            }
        }
        .sheet(item: $editing) { record in
            NavigationStack {
                CFDnsEditorView(zone: zone, record: record) {
                    Task { await loadDNS() }
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.92), in: Capsule())
                    .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.red.opacity(0.9), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    private var filteredRecords: [CFDnsRecord] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return records }
        return records.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.content.localizedCaseInsensitiveContains(q)
                || $0.type.localizedCaseInsensitiveContains(q)
        }
    }

    private func dnsRow(_ record: CFDnsRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(record.type)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(accent)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(record.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text("TTL \(record.ttlLabel)")
                    if record.proxied {
                        Label("代理", systemImage: "cloud.fill")
                    }
                    if let p = record.priority {
                        Text("优先 \(p)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func loadDNS() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            records = try await service.listDNSRecords(cred: CFCredentials(settings: settings), zoneId: zone.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRecord(_ record: CFDnsRecord) async {
        do {
            try await service.deleteDNSRecord(
                cred: CFCredentials(settings: settings),
                zoneId: zone.id,
                recordId: record.id
            )
            records.removeAll { $0.id == record.id }
            flash("已删除")
            Haptics.light()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func purge() async {
        isPurging = true
        defer { isPurging = false }
        do {
            try await service.purgeEverything(cred: CFCredentials(settings: settings), zoneId: zone.id)
            flash("缓存已清除")
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func flash(_ msg: String) {
        withAnimation { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { if toast == msg { toast = nil } }
        }
    }
}

// MARK: - DNS Editor

struct CFDnsEditorView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let zone: CFZone
    let record: CFDnsRecord?
    var onSaved: () -> Void

    @State private var type = "A"
    @State private var name = ""
    @State private var content = ""
    @State private var ttl = 1
    @State private var proxied = false
    @State private var priority = 10
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let service = CloudflareService.shared
    private var isNew: Bool { record == nil }

    var body: some View {
        Form {
            Section("记录") {
                Picker("类型", selection: $type) {
                    ForEach(CFDnsTypes.common, id: \.self) { Text($0).tag($0) }
                }
                TextField("名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("内容", text: $content, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("选项") {
                Picker("TTL", selection: $ttl) {
                    Text("自动").tag(1)
                    Text("1 分钟").tag(60)
                    Text("5 分钟").tag(300)
                    Text("1 小时").tag(3600)
                    Text("1 天").tag(86400)
                }
                if type == "A" || type == "AAAA" || type == "CNAME" {
                    Toggle("Cloudflare 代理", isOn: $proxied)
                }
                if type == "MX" {
                    Stepper("优先级 \(priority)", value: $priority, in: 0...65535)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle(isNew ? "添加 DNS" : "编辑 DNS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(isSaving || name.isEmpty || content.isEmpty)
            }
        }
        .onAppear {
            if let record {
                type = record.type
                name = record.name
                content = record.content
                ttl = record.ttl
                proxied = record.proxied
                priority = record.priority ?? 10
            } else {
                name = zone.name
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let input = CFDnsRecordInput(
            type: type,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            ttl: ttl,
            proxied: (type == "A" || type == "AAAA" || type == "CNAME") ? proxied : false,
            priority: type == "MX" ? priority : nil
        )
        do {
            let cred = CFCredentials(settings: settings)
            if let record {
                _ = try await service.updateDNSRecord(
                    cred: cred,
                    zoneId: zone.id,
                    recordId: record.id,
                    input: input
                )
            } else {
                _ = try await service.createDNSRecord(
                    cred: cred,
                    zoneId: zone.id,
                    input: input
                )
            }
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
