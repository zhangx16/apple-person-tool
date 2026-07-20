import SwiftUI
import SwiftData

/// Streaming chat thread: bubbles, composer, model picker, stop / copy, Imagine entry.
struct ChatThreadView: View {
    let conversationID: UUID
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var imagineVM = ImagineViewModel()
    @State private var showImagine = false
    @State private var actionPayload: AppActionPayload?
    @State private var showActionRunner = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if let banner = viewModel.errorMessage, viewModel.active?.id == conversationID {
                    errorBanner(banner)
                }
                if let payload = actionPayload {
                    chatActionBanner(payload)
                }
                messageList
            }
            composer
        }
        .background(AppSurfaceBackground(accent: Color.accentColor))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelChip
            }
        }
        .sheet(isPresented: $viewModel.showModelPicker) {
            ModelPickerSheet(
                models: viewModel.availableModels,
                selected: viewModel.active?.model ?? settings.preferredModel
            ) { model in
                viewModel.selectModel(model)
                viewModel.showModelPicker = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showImagine) {
            ImagineComposeView(
                viewModel: imagineVM,
                conversationID: conversationID
            ) {
                viewModel.loadConversation(id: conversationID)
                viewModel.reload()
            }
            .environmentObject(settings)
            .presentationDetents([.large, .medium])
        }
        .sheet(isPresented: $showActionRunner) {
            if let payload = actionPayload {
                NavigationStack {
                    QuickActionRunnerView(payload: payload)
                        .environmentObject(settings)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showActionRunner = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onChange(of: viewModel.input) { _, newValue in
            actionPayload = ActionRouter.parseChatCommand(newValue)
        }
        .onAppear {
            viewModel.loadConversation(id: conversationID)
            imagineVM.attach(modelContext: modelContext, settings: settings)
            imagineVM.onConversationUpdated = { [weak viewModel] id in
                viewModel?.loadConversation(id: id)
                viewModel?.reload()
            }
            Task { await viewModel.loadModels() }
        }
        .onDisappear {
            // Keep streaming if user pops — stop only via explicit 停止.
        }
    }

    // MARK: - Chat → action

    private func chatActionBanner(_ payload: AppActionPayload) -> some View {
        HStack(spacing: 10) {
            Image(systemName: payload.action.systemImage)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到可执行动作")
                    .font(.caption.weight(.semibold))
                Text(payload.action.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("执行") {
                showActionRunner = true
                Haptics.light()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                actionPayload = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
    }

    // MARK: - Model chip

    private var modelChip: some View {
        Button {
            viewModel.showModelPicker = true
            Task { await viewModel.loadModels() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor.brandGradient)
                    .symbolEffect(.pulse, options: .repeating, isActive: viewModel.isStreaming)
                Text(viewModel.active?.model ?? settings.preferredModel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule()
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(viewModel.isStreaming)
        .accessibilityLabel("选择模型，当前 \(viewModel.active?.model ?? settings.preferredModel)")
        .accessibilityHint("打开模型列表")
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppleTheme.chatSpacing) {
                    let messages = viewModel.active?.id == conversationID
                        ? (viewModel.active?.messages ?? [])
                        : []
                    if messages.isEmpty {
                        EmptyStateView(
                            symbol: "text.bubble",
                            title: "发送第一条消息",
                            message: "与 Grok 开始对话吧。"
                        )
                        .frame(minHeight: 240)
                    } else {
                        ForEach(messages) { message in
                            Group {
                                if message.hasMedia {
                                    MediaBubbleView(
                                        message: message,
                                        onCopyCaption: { viewModel.copyMessage(message) }
                                    )
                                } else {
                                    MessageBubbleView(
                                        message: message,
                                        onCopy: { viewModel.copyMessage(message) }
                                    )
                                }
                            }
                            .id(message.id)
                            .transition(AppleTheme.bubbleTransition(reduceMotion: reduceMotion))
                        }
                    }
                    Color.clear.frame(height: 76).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .animation(AppleTheme.insertAnimation(reduceMotion: reduceMotion), value: viewModel.active?.messages.count)
            }
            .onChange(of: viewModel.active?.messages.last?.content) { _, _ in
                withAnimation(AppleTheme.snappyAnimation(reduceMotion: reduceMotion)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.active?.messages.count) { _, _ in
                withAnimation(AppleTheme.snappyAnimation(reduceMotion: reduceMotion)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if viewModel.isStreaming {
                Button {
                    viewModel.stop()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.caption.weight(.bold))
                        Text("停止生成")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.brandGradient, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                    }
                    .modifier(AppShadow.near())
                }
                .buttonStyle(PressableButtonStyle())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityLabel("停止")
                .accessibilityHint("停止生成回复")
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    imagineVM.attach(modelContext: modelContext, settings: settings)
                    showImagine = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(settings.isAIConfigured && !viewModel.isStreaming ? .white : Color.secondary)
                        .frame(width: 36, height: 36)
                        .background {
                            if settings.isAIConfigured && !viewModel.isStreaming {
                                Circle().fill(Color.accentColor.brandGradient)
                            } else {
                                Circle().fill(Color(.tertiarySystemFill))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!settings.isAIConfigured || viewModel.isStreaming)
                .accessibilityLabel("创作")
                .accessibilityHint("打开生图、编辑或视频创作")

                TextField("发送消息…", text: $viewModel.input, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...6)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .disabled(viewModel.isStreaming)
                    .accessibilityLabel("消息输入")

                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(canSend ? .white : Color.secondary)
                        .frame(width: 36, height: 36)
                        .background {
                            if canSend {
                                Circle().fill(Color.accentColor.brandGradient)
                            } else {
                                Circle().fill(Color(.tertiarySystemFill))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canSend)
                .accessibilityLabel("发送")
                .accessibilityHint("发送消息")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppStroke.highlight, lineWidth: 1)
            }
            .modifier(AppShadow.far())
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .animation(AppleTheme.preferredSnappy, value: viewModel.isStreaming)
    }

    private var canSend: Bool {
        !viewModel.isStreaming
            && !viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && settings.isAIConfigured
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .lineLimit(3)
                .accessibilityLabel("错误：\(text)")
            Spacer(minLength: 4)
            Button("关闭") { viewModel.errorMessage = nil }
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("关闭错误提示")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
        }
        .modifier(AppShadow.mid())
        .padding(.horizontal, 14)
        .padding(.top, 10)
        // Keep dismiss as its own VO target (do not combine into static text).
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Bubble

struct MessageBubbleView: View {
    let message: ChatMessage
    var onCopy: () -> Void

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    if message.content.isEmpty && message.isStreaming {
                        StreamingCursor()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        Text(message.content)
                            .font(.body)
                            .foregroundStyle(isUser ? Color.white : Color.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        if message.isStreaming {
                            StreamingCursor()
                                .padding(.trailing, 8)
                                .padding(.bottom, 10)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: AppleTheme.bubbleRadius, style: .continuous)
                        .fill(isUser ? AnyShapeStyle(AppleTheme.userBubble.brandGradient) : AnyShapeStyle(AppleTheme.assistantBubble))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppleTheme.bubbleRadius, style: .continuous)
                        .strokeBorder(AppStroke.highlight, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }
            if !isUser { Spacer(minLength: 48) }
        }
        .contextMenu {
            if !message.content.isEmpty {
                Button {
                    onCopy()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(message.isStreaming ? "正在流式生成" : "长按可复制")
        .accessibilityAddTraits(message.isStreaming ? .updatesFrequently : [])
    }

    private var accessibilityLabel: String {
        let role = isUser ? "我" : "助手"
        if message.isStreaming {
            if message.content.isEmpty {
                return "\(role)，正在生成"
            }
            return "\(role)，正在生成：\(message.content)"
        }
        return "\(role)：\(message.content)"
    }
}

// MARK: - Streaming cursor

struct StreamingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = true

    var body: some View {
        Capsule()
            .fill(Color.secondary)
            .frame(width: 7, height: 16)
            .opacity(reduceMotion ? 1 : (on ? 1 : 0.2))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    on = false
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Model picker

struct ModelPickerSheet: View {
    let models: [String]
    let selected: String
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(models, id: \.self) { model in
                        Button {
                            onSelect(model)
                        } label: {
                            HStack {
                                Text(model)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if model == selected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityLabel(model)
                        .accessibilityAddTraits(model == selected ? .isSelected : [])
                    }
                } header: {
                    Text("文本模型")
                } footer: {
                    Text("Imagine 媒体模型请从创作入口「+」选择，不混入文本列表。")
                }
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatThreadView(
            conversationID: UUID(),
            viewModel: ChatViewModel()
        )
    }
    .environmentObject(AppSettings.shared)
}
