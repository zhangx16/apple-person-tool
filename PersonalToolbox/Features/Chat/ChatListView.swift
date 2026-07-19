import SwiftUI
import SwiftData

/// Conversation list for the 助手 tab. Push → `ChatThreadView`.
struct ChatListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @Binding var selectedTab: AppTab

    @StateObject private var viewModel = ChatViewModel()
    @State private var path = NavigationPath()
    @State private var renameTarget: ChatConversation?
    @State private var renameText = ""

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !settings.isAIConfigured {
                    EmptyStateView(
                        symbol: "key.fill",
                        title: "配置 API Key",
                        message: "在设置中填写 sub2api 的 Base URL 与 API Key 后即可开始对话。",
                        actionTitle: "前往设置"
                    ) {
                        selectedTab = .settings
                    }
                } else if viewModel.conversations.isEmpty {
                    EmptyStateView(
                        symbol: "bubble.left.and.bubble.right",
                        title: "开始一段新对话",
                        message: "点右上角「新建」或下方按钮创建会话。",
                        actionTitle: "新建对话"
                    ) {
                        createAndOpen()
                    }
                } else {
                    conversationList
                }
            }
            .background(AppSurfaceBackground(accent: Color.accentColor))
            .navigationTitle("助手")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createAndOpen()
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.gradient, in: Circle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!settings.isAIConfigured)
                    .opacity(settings.isAIConfigured ? 1 : 0.45)
                    .accessibilityLabel("新建对话")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ChatThreadView(conversationID: id, viewModel: viewModel)
            }
            .alert(
                "错误",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil && path.isEmpty },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "重命名会话",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField("标题", text: $renameText)
                Button("取消", role: .cancel) { renameTarget = nil }
                Button("保存") {
                    if let target = renameTarget {
                        viewModel.renameConversation(id: target.id, title: renameText)
                    }
                    renameTarget = nil
                }
            }
        }
        .onAppear {
            viewModel.attach(modelContext: modelContext, settings: settings)
            viewModel.reload()
        }
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.conversations) { conv in
                    Button {
                        path.append(conv.id)
                    } label: {
                        ConversationRow(conversation: conv)
                            .appCard()
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.98))
                    .contextMenu {
                        Button {
                            renameText = conv.title
                            renameTarget = conv
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            viewModel.deleteConversation(id: conv.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private func createAndOpen() {
        guard settings.isAIConfigured else {
            selectedTab = .settings
            return
        }
        viewModel.attach(modelContext: modelContext, settings: settings)
        if let conv = viewModel.newConversation() {
            path.append(conv.id)
        }
    }
}

// MARK: - Row

private struct ConversationRow: View {
    let conversation: ChatConversation

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(conversation.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Self.relativeDate(conversation.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.title)，\(Self.relativeDate(conversation.updatedAt))，模型 \(conversation.model)")
        .accessibilityHint("打开对话")
    }

    private static func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "昨天"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            f.dateFormat = "M月d日"
        } else {
            f.dateFormat = "yyyy/M/d"
        }
        return f.string(from: date)
    }
}

#Preview {
    ChatListView(selectedTab: .constant(.chat))
        .environmentObject(AppSettings.shared)
        .modelContainer(for: [ConversationEntity.self, MessageEntity.self], inMemory: true)
}
