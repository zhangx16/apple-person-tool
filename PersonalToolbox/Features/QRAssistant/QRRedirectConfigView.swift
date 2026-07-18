import SwiftUI

/// 跳转规则与订阅设置。
struct QRRedirectConfigView: View {
    @ObservedObject var store: QRAssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingRule: QRRedirectRule?
    @State private var showAdd = false
    @State private var isRefreshing = false

    private let accent = QRRedirectDefaults.accent

    var body: some View {
        List {
            Section {
                Toggle("识别后智能跳转", isOn: Binding(
                    get: { store.settings.autoRedirect },
                    set: { store.setAutoRedirect($0) }
                ))
                Toggle("启用兜底 Scheme", isOn: Binding(
                    get: { store.settings.fallbackEnabled },
                    set: { store.setFallback(enabled: $0) }
                ))
                if store.settings.fallbackEnabled {
                    TextField("兜底 URL Scheme（可用 {content}）", text: Binding(
                        get: { store.settings.fallbackUrlScheme },
                        set: { store.setFallback(enabled: store.settings.fallbackEnabled, scheme: $0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
                }
            } header: {
                Text("行为")
            } footer: {
                Text("匹配到规则后会尝试打开对应 App；未安装时系统可能无反应。")
            }

            Section {
                TextField("订阅 JSON 地址", text: Binding(
                    get: { store.settings.subscriptionUrl },
                    set: { store.setSubscriptionUrl($0) }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                Button {
                    Task {
                        isRefreshing = true
                        await store.refreshSubscription()
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label("拉取并合并远程规则", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(store.settings.subscriptionUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRefreshing)

                if let err = store.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("远程订阅")
            } footer: {
                Text("远程应为 RedirectRule 数组 JSON（appName / keyword / urlScheme / iconUrl）。")
            }

            Section {
                ForEach(store.settings.redirectRules) { rule in
                    Button {
                        editingRule = rule
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rule.appName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if rule.source == .remote {
                                    Text("远程")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(rule.keyword)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(rule.urlScheme)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { indexSet in
                    let ids = indexSet.compactMap { store.settings.redirectRules[safe: $0]?.id }
                    for id in ids { store.deleteRule(id: id) }
                }
                .onMove(perform: store.moveRules)

                Button {
                    showAdd = true
                } label: {
                    Label("添加规则", systemImage: "plus.circle.fill")
                }
                .foregroundStyle(accent)

                Button("恢复内置规则") {
                    store.resetRulesToDefault()
                }
            } header: {
                Text("规则列表（\(store.settings.redirectRules.count)）")
            } footer: {
                Text("按列表顺序优先匹配。关键字用英文或中文逗号分隔，内容包含任一词即命中。")
            }
        }
        .navigationTitle("跳转设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                QRRuleEditorView(store: store, rule: nil)
            }
        }
        .sheet(item: $editingRule) { rule in
            NavigationStack {
                QRRuleEditorView(store: store, rule: rule)
            }
        }
    }
}

struct QRRuleEditorView: View {
    @ObservedObject var store: QRAssistantStore
    let rule: QRRedirectRule?
    @Environment(\.dismiss) private var dismiss

    @State private var appName = ""
    @State private var keyword = ""
    @State private var urlScheme = ""
    @State private var iconUrl = ""

    private var isNew: Bool { rule == nil }

    var body: some View {
        Form {
            Section("展示") {
                TextField("应用名称", text: $appName)
                TextField("图标 URL（可选）", text: $iconUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("匹配") {
                TextField("关键字（逗号分隔）", text: $keyword, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
            }
            Section("跳转") {
                TextField("URL Scheme", text: $urlScheme, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("可用占位符 {content} / {url} 插入扫码原文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !isNew {
                Section {
                    Button("删除规则", role: .destructive) {
                        if let rule {
                            store.deleteRule(id: rule.id)
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "添加规则" : "编辑规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
            }
        }
        .onAppear {
            if let rule {
                appName = rule.appName
                keyword = rule.keyword
                urlScheme = rule.urlScheme
                iconUrl = rule.iconUrl ?? ""
            }
        }
    }

    private var canSave: Bool {
        !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !urlScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let saved = QRRedirectRule(
            id: rule?.id ?? UUID().uuidString,
            keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            urlScheme: urlScheme.trimmingCharacters(in: .whitespacesAndNewlines),
            appName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
            iconUrl: iconUrl.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            source: rule?.source ?? .local
        )
        store.upsertRule(saved)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
