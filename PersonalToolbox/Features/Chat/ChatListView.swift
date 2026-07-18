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
            .background(AppleTheme.canvas)
            .navigationTitle("助手")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createAndOpen()
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!settings.isAIConfigured)
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
        List {
            ForEach(viewModel.conversations) { conv in
                Button {
                    path.append(conv.id)
                } label: {
                    ConversationRow(conversation: conv)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteConversation(id: conv.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(conversation.model)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Self.relativeDate(conversation.updatedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
