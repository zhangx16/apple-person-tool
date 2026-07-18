import SwiftUI

/// Messages for a selected mailbox. Folder segmented control + skip/top pagination.
struct InboxView: View {
    @ObservedObject var viewModel: MailViewModel
    let account: MailAccount

    var body: some View {
        Group {
            if viewModel.isLoadingMessages && viewModel.messages.isEmpty {
                ProgressView("加载邮件…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.messagesError, viewModel.messages.isEmpty {
                errorState(message: error)
            } else if viewModel.messages.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: "暂无邮件",
                    message: "「\(viewModel.selectedFolder.title)」中没有邮件。"
                )
            } else {
                messageList
            }
        }
        .background(AppleTheme.canvas)
        .navigationTitle(account.email)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("文件夹", selection: folderBinding) {
                    ForEach(MailViewModel.MailFolder.allCases) { folder in
                        Text(folder.title).tag(folder)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        }
        .task {
            viewModel.selectAccount(account)
            await viewModel.loadMessages(force: true)
        }
    }

    private var folderBinding: Binding<MailViewModel.MailFolder> {
        Binding(
            get: { viewModel.selectedFolder },
            set: { newValue in
                Task { await viewModel.changeFolder(newValue) }
            }
        )
    }

    private var messageList: some View {
        List {
            ForEach(viewModel.messages) { message in
                NavigationLink {
                    MessageDetailView(viewModel: viewModel, messageID: message.id)
                } label: {
                    MessageRow(message: message)
                }
            }

            if viewModel.messagesHasMore {
                Button {
                    Task { await viewModel.loadMoreMessages() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMoreMessages {
                            ProgressView()
                                .controlSize(.small)
                            Text("加载中…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("加载更多")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .disabled(viewModel.isLoadingMoreMessages)
            }

            if let error = viewModel.messagesError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.refreshMessages()
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "无法加载邮件",
                message: message
            )
            Button {
                Haptics.light()
                Task { await viewModel.refreshMessages() }
            } label: {
                PrimaryButtonLabel(title: "重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

private struct MessageRow: View {
    let message: MailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(message.from.isEmpty ? "(未知发件人)" : message.from)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(message.displayDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(message.subject)
                .font(.body)
                .lineLimit(1)
            if !message.preview.isEmpty {
                Text(message.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("打开邮件详情")
    }

    private var accessibilityLabel: String {
        let from = message.from.isEmpty ? "未知发件人" : message.from
        let subject = message.subject.isEmpty ? "无主题" : message.subject
        var parts = [subject, "来自 \(from)", message.displayDate]
        if !message.preview.isEmpty {
            parts.append(message.preview)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "，")
    }
}

#Preview {
    NavigationStack {
        InboxView(
            viewModel: MailViewModel(),
            account: MailAccount(email: "demo@example.com")
        )
    }
    .environmentObject(AppSettings.shared)
}
