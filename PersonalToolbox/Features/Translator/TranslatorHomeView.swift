import SwiftUI
import UIKit

/// 多引擎翻译面板（参考 Translator.scripting，默认走 sub2api）。
struct TranslatorHomeView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var store = TranslatorStore.shared

    @State private var sourceText = ""
    @State private var results: [TranslatorEngineResult] = []
    @State private var isTranslating = false
    @State private var showSettings = false
    @State private var toast: String?
    @FocusState private var inputFocused: Bool

    private let accent = TranslatorAccent.color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                languageBar
                inputCard
                actionBar
                resultsSection
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppleTheme.canvas)
        .navigationTitle("翻译器")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .translator, title: "翻译器")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("翻译设置")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { inputFocused = false }
            }
        }
        .onAppear {
            if !store.isLoaded {
                store.load(appSettings: appSettings)
            } else {
                store.syncSub2Placeholders(from: appSettings)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                TranslatorSettingsView(store: store)
                    .environmentObject(appSettings)
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
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AppleTheme.preferredSnappy, value: toast)
    }

    // MARK: - Language

    private var languageBar: some View {
        HStack(spacing: 8) {
            languageMenu(
                title: "源语言",
                selection: Binding(
                    get: { store.sourceLanguageCode },
                    set: { store.sourceLanguageCode = $0; store.saveLanguages() }
                ),
                includeAuto: true
            )

            Button {
                store.swapLanguages()
                Haptics.light()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .accessibilityLabel("交换语种")
            .disabled(store.sourceLanguageCode == TranslatorLanguage.auto.code)

            languageMenu(
                title: "目标",
                selection: Binding(
                    get: { store.targetLanguageCode },
                    set: { store.targetLanguageCode = $0; store.saveLanguages() }
                ),
                includeAuto: false
            )
        }
    }

    private func languageMenu(title: String, selection: Binding<String>, includeAuto: Bool) -> some View {
        let options = TranslatorLanguage.all.filter { includeAuto || $0.code != TranslatorLanguage.auto.code }
        return Menu {
            ForEach(options) { lang in
                Button {
                    selection.wrappedValue = lang.code
                } label: {
                    if selection.wrappedValue == lang.code {
                        Label(lang.label, systemImage: "checkmark")
                    } else {
                        Text(lang.label)
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(TranslatorLanguage.find(selection.wrappedValue).label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("原文")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !sourceText.isEmpty {
                    Button("清空") {
                        sourceText = ""
                        results = []
                    }
                    .font(.caption)
                }
            }
            TextField("输入或粘贴要翻译的文本…", text: $sourceText, axis: .vertical)
                .lineLimit(6...14)
                .focused($inputFocused)
                .textInputAutocapitalization(.never)
        }
        .padding(14)
        .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                if let clip = UIPasteboard.general.string, !clip.isEmpty {
                    sourceText = clip
                    flashToast("已粘贴")
                } else {
                    flashToast("剪贴板为空")
                }
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                Task { await runTranslate() }
            } label: {
                if isTranslating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("翻译", systemImage: "translate")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(isTranslating || sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        let enabled = store.enabledEngines
        if enabled.isEmpty {
            ContentUnavailableView(
                "没有启用的引擎",
                systemImage: "switch.2",
                description: Text("请在设置中开启至少一个翻译引擎")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else if results.isEmpty && !isTranslating {
            Text("启用引擎：\(enabled.map(\.label).joined(separator: "、"))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 12) {
                ForEach(results) { result in
                    resultCard(result)
                }
            }
        }
    }

    private func resultCard(_ result: TranslatorEngineResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: result.systemImage)
                    .foregroundStyle(accent)
                Text(result.engineName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if result.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                } else if !result.translatedText.isEmpty {
                    Button {
                        UIPasteboard.general.string = result.translatedText
                        flashToast("已复制")
                        Haptics.success()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        Task { await rerun(engineId: result.engineId) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                } else if !result.errorText.isEmpty {
                    Button {
                        Task { await rerun(engineId: result.engineId) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if result.isTranslating {
                Text("翻译中…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if !result.errorText.isEmpty {
                Text(result.errorText)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else {
                Text(result.translatedText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    // MARK: - Actions

    private func runTranslate() async {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputFocused = false

        let engines = store.enabledEngines
        guard !engines.isEmpty else {
            flashToast("请先启用引擎")
            return
        }

        isTranslating = true
        results = engines.map {
            TranslatorEngineResult(
                engineId: $0.id,
                engineName: $0.label,
                systemImage: $0.systemImage,
                translatedText: "",
                errorText: "",
                isTranslating: true
            )
        }

        let request = TranslatorRequest(
            sourceText: text,
            sourceLanguageCode: store.sourceLanguageCode,
            targetLanguageCode: store.targetLanguageCode
        )
        let sub2Fallback = TranslatorService.Sub2Fallback(
            baseURL: appSettings.sub2apiBaseURL,
            apiKey: appSettings.sub2apiAPIKey,
            model: appSettings.preferredModel
        )

        await withTaskGroup(of: (String, Result<String, Error>).self) { group in
            for engine in engines {
                group.addTask {
                    do {
                        let out = try await TranslatorService.translate(
                            engine: engine,
                            request: request,
                            sub2Fallback: sub2Fallback
                        )
                        return (engine.id, .success(out))
                    } catch {
                        return (engine.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                results = results.map { item in
                    guard item.engineId == id else { return item }
                    var next = item
                    next.isTranslating = false
                    switch result {
                    case .success(let text):
                        next.translatedText = text
                        next.errorText = ""
                    case .failure(let error):
                        next.translatedText = ""
                        next.errorText = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                    }
                    return next
                }
            }
        }

        isTranslating = false
        if results.contains(where: { !$0.translatedText.isEmpty }) {
            Haptics.success()
        } else {
            Haptics.error()
        }
    }

    private func rerun(engineId: String) async {
        guard let engine = store.engines.first(where: { $0.id == engineId }) else { return }
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        results = results.map { item in
            guard item.engineId == engineId else { return item }
            var next = item
            next.isTranslating = true
            next.errorText = ""
            next.translatedText = ""
            return next
        }

        let request = TranslatorRequest(
            sourceText: text,
            sourceLanguageCode: store.sourceLanguageCode,
            targetLanguageCode: store.targetLanguageCode
        )
        let sub2Fallback = TranslatorService.Sub2Fallback(
            baseURL: appSettings.sub2apiBaseURL,
            apiKey: appSettings.sub2apiAPIKey,
            model: appSettings.preferredModel
        )
        do {
            let out = try await TranslatorService.translate(
                engine: engine,
                request: request,
                sub2Fallback: sub2Fallback
            )
            results = results.map { item in
                guard item.engineId == engineId else { return item }
                var next = item
                next.isTranslating = false
                next.translatedText = out
                next.errorText = ""
                return next
            }
            Haptics.success()
        } catch {
            results = results.map { item in
                guard item.engineId == engineId else { return item }
                var next = item
                next.isTranslating = false
                next.errorText = error.localizedDescription
                return next
            }
            Haptics.error()
        }
    }

    private func flashToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }
}
