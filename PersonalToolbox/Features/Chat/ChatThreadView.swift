import SwiftUI
import SwiftData

/// Streaming chat thread: bubbles, composer, model picker, stop / copy, Imagine entry.
struct ChatThreadView: View {
    let conversationID: UUID
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var modelContext

    @StateObject private var imagineVM = ImagineViewModel()
    @State private var showImagine = false

    var body: some View {
        VStack(spacing: 0) {
            if let banner = viewModel.errorMessage, viewModel.active?.id == conversationID {
                errorBanner(banner)
            }
            messageList
            Divider()
            composer
        }
        .background(AppleTheme.canvas)
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

    // MARK: - Model chip

    private var modelChip: some View {
        Button {
            viewModel.showModelPicker = true
            Task { await viewModel.loadModels() }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.active?.model ?? settings.preferredModel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppleTheme.assistantBubble, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(viewModel.isStreaming)
        .accessibilityLabel("选择模型")
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
                        }
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.active?.messages.last?.content) { _, _ in
                withAnimation(AppleTheme.snappy) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.active?.messages.count) { _, _ in
                withAnimation(AppleTheme.snappy) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if viewModel.isStreaming {
                HStack {
                    Button {
                        viewModel.stop()
                    } label: {
                        Label("停止", systemImage: "stop.circle.fill")
                            .font(.body.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    imagineVM.attach(modelContext: modelContext, settings: settings)
                    showImagine = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(settings.isAIConfigured && !viewModel.isStreaming ? Color.accentColor : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!settings.isAIConfigured || viewModel.isStreaming)
                .accessibilityLabel("创作")

                TextField("发送消息…", text: $viewModel.input, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppleTheme.assistantBubble, in: RoundedRectangle(cornerRadius: AppleTheme.controlRadius, style: .continuous))
                    .disabled(viewModel.isStreaming)

                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canSend)
                .accessibilityLabel("发送")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var canSend: Bool {
        !viewModel.isStreaming
            && !viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && settings.isAIConfigured
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .font(.footnote)
                .lineLimit(3)
            Spacer(minLength: 4)
            Button("关闭") { viewModel.errorMessage = nil }
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        if message.isStreaming {
                            StreamingCursor()
                                .padding(.trailing, 8)
                                .padding(.bottom, 10)
                        }
                    }
                }
                .background(
                    isUser ? AppleTheme.userBubble : AppleTheme.assistantBubble,
                    in: RoundedRectangle(cornerRadius: AppleTheme.bubbleRadius, style: .continuous)
                )
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
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let role = isUser ? "我" : "助手"
        if message.isStreaming {
            return "\(role)，正在生成"
        }
        return "\(role)：\(message.content)"
    }
}

// MARK: - Streaming cursor

struct StreamingCursor: View {
    @State private var on = true

    var body: some View {
        Capsule()
            .fill(Color.secondary)
            .frame(width: 7, height: 16)
            .opacity(on ? 1 : 0.2)
            .onAppear {
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
                                }
                            }
                        }
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
