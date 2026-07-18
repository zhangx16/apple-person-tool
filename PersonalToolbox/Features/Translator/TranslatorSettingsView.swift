import SwiftUI

struct TranslatorSettingsView: View {
    @ObservedObject var store: TranslatorStore
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var editing: TranslatorEngine?
    @State private var showAddAI = false

    private let accent = TranslatorAccent.color

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ServiceBrandIcon(brand: .translator, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("翻译器")
                            .font(.headline)
                        Text("多引擎并行 · 默认 Sub2API")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(store.engines) { engine in
                    engineRow(engine)
                }
                .onMove(perform: store.moveEngines)
                .onDelete { indexSet in
                    for i in indexSet {
                        let id = store.engines[i].id
                        store.deleteEngine(id: id)
                    }
                }

                Button {
                    showAddAI = true
                } label: {
                    Label("添加 AI 接口", systemImage: "plus.circle.fill")
                }
                .foregroundStyle(accent)

                Button("恢复默认引擎") {
                    store.resetToDefaults(app: appSettings)
                }
            } header: {
                Text("引擎（\(store.engines.count)）")
            } footer: {
                Text("Sub2API 引擎在未单独填写时，会使用「设置」里的 sub2api 地址、API Key 与默认模型。可上下拖动调整显示顺序。")
            }

            Section("说明") {
                LabeledContent("Sub2API", value: appSettings.sub2apiBaseURL)
                LabeledContent("默认模型", value: appSettings.preferredModel)
                Text("Google 网页翻译为非官方接口，可能不稳定；请仅个人使用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("翻译设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .sheet(item: $editing) { engine in
            NavigationStack {
                TranslatorEngineEditorView(store: store, engine: engine)
                    .environmentObject(appSettings)
            }
        }
        .sheet(isPresented: $showAddAI) {
            NavigationStack {
                TranslatorEngineEditorView(store: store, engine: nil)
                    .environmentObject(appSettings)
            }
        }
    }

    private func engineRow(_ engine: TranslatorEngine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: engine.systemImage)
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.label)
                    .font(.body.weight(.semibold))
                Text(subtitle(for: engine))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { engine.enabled },
                set: { store.setEngineEnabled(id: engine.id, enabled: $0) }
            ))
            .labelsHidden()
            Button {
                editing = engine
            } label: {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func subtitle(for engine: TranslatorEngine) -> String {
        switch engine.kind {
        case .google:
            return "网页接口 · 无需 Key"
        case .sub2api:
            let model = (engine.model?.isEmpty == false ? engine.model! : appSettings.preferredModel)
            return "AI · \(model)"
        case .aiApi:
            let mode = engine.compatibilityMode?.label ?? "AI"
            let model = engine.model ?? "未设模型"
            return "\(mode) · \(model)"
        }
    }
}

// MARK: - Engine editor

struct TranslatorEngineEditorView: View {
    @ObservedObject var store: TranslatorStore
    let engine: TranslatorEngine?
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var kind: TranslatorEngineKind = .aiApi
    @State private var mode: TranslatorAiMode = .newapi
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var enabled = true

    private var isNew: Bool { engine == nil }
    private var isGoogle: Bool { (engine?.kind == .google) || kind == .google }

    var body: some View {
        Form {
            Section("基本") {
                TextField("显示名称", text: $label)
                if isNew {
                    Picker("类型", selection: $kind) {
                        Text("AI 接口").tag(TranslatorEngineKind.aiApi)
                        Text("Sub2API 预设").tag(TranslatorEngineKind.sub2api)
                        Text("Google 网页").tag(TranslatorEngineKind.google)
                    }
                } else {
                    LabeledContent("类型", value: kindLabel)
                }
                Toggle("启用", isOn: $enabled)
            }

            if !isGoogle {
                Section {
                    if kind == .aiApi || engine?.kind == .aiApi {
                        Picker("兼容模式", selection: $mode) {
                            ForEach(TranslatorAiMode.allCases) { m in
                                Text(m.label).tag(m)
                            }
                        }
                    }
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                    TextField("模型", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if kind == .sub2api || engine?.kind == .sub2api {
                        Button("填入 App 设置中的 Sub2API") {
                            baseURL = appSettings.sub2apiBaseURL
                            apiKey = appSettings.sub2apiAPIKey
                            model = appSettings.preferredModel
                        }
                    }
                } header: {
                    Text("接口")
                } footer: {
                    Text("Sub2API / NewAPI 一般使用 /v1/chat/completions。留空时 Sub2API 引擎会回落到全局设置。")
                }
            }

            if !isNew, engine?.kind != .sub2api || store.engines.count > 1 {
                Section {
                    Button("删除引擎", role: .destructive) {
                        if let engine {
                            store.deleteEngine(id: engine.id)
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "添加引擎" : "编辑引擎")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear(perform: populate)
    }

    private var kindLabel: String {
        switch engine?.kind {
        case .sub2api: return "Sub2API"
        case .google: return "Google"
        case .aiApi: return "AI 接口"
        case .none: return ""
        }
    }

    private func populate() {
        guard let engine else {
            label = "自定义 AI"
            kind = .aiApi
            mode = .newapi
            baseURL = appSettings.sub2apiBaseURL
            apiKey = appSettings.sub2apiAPIKey
            model = appSettings.preferredModel
            return
        }
        label = engine.label
        kind = engine.kind
        mode = engine.compatibilityMode ?? .newapi
        baseURL = engine.baseURL ?? ""
        apiKey = engine.apiKey ?? ""
        model = engine.model ?? ""
        enabled = engine.enabled
    }

    private func save() {
        let resolvedKind = engine?.kind ?? kind
        let image: String = {
            switch resolvedKind {
            case .sub2api: return "sparkles"
            case .google: return "g.circle"
            case .aiApi: return "cpu"
            }
        }()
        let saved = TranslatorEngine(
            id: engine?.id ?? UUID().uuidString,
            kind: resolvedKind,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            systemImage: image,
            enabled: enabled,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            baseURL: baseURL.isEmpty ? nil : baseURL,
            model: model.isEmpty ? nil : model,
            compatibilityMode: resolvedKind == .google ? nil : mode
        )
        store.upsertEngine(saved)
        dismiss()
    }
}
