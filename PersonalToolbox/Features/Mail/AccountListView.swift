import SwiftUI

/// Mail tab root: session account pool, or external virtual mailboxes (default + favorites).
struct AccountListView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = MailViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isUnconfigured || (!settings.isMailConfigured && viewModel.accounts.isEmpty) {
                    unconfiguredState
                } else if viewModel.isLoadingAccounts && viewModel.accounts.isEmpty {
                    ProgressView("加载邮箱账号…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.accountsError, viewModel.accounts.isEmpty {
                    errorState(message: error)
                } else if viewModel.accounts.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: settings.mailUseExternalAPI ? "未配置邮箱" : "邮箱池为空",
                        message: settings.mailUseExternalAPI
                            ? "请在设置中填写默认邮箱，可选添加收藏邮箱。"
                            : "服务端尚未添加任何邮箱账号。"
                    )
                } else {
                    accountList
                }
            }
            .background(AppleTheme.canvas)
            .navigationTitle("邮件")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isLoadingAccounts {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .task {
                await viewModel.loadAccounts(force: true)
            }
            .onChange(of: settings.mailUseExternalAPI) { _, _ in
                Task { await viewModel.loadAccounts(force: true) }
            }
            .onChange(of: settings.mailPassword) { _, _ in
                Task { await viewModel.loadAccounts(force: true) }
            }
            .onChange(of: settings.mailExternalAPIKey) { _, _ in
                Task { await viewModel.loadAccounts(force: true) }
            }
            .onChange(of: settings.mailDefaultEmail) { _, _ in
                Task { await viewModel.loadAccounts(force: true) }
            }
            .onChange(of: settings.mailFavoriteEmails) { _, _ in
                Task { await viewModel.loadAccounts(force: true) }
            }
        }
    }

    // MARK: - Subviews

    private var accountList: some View {
        List {
            if settings.mailUseExternalAPI {
                Section {
                    Text("外部 API 模式：列表与详情均携带邮箱参数；默认邮箱与收藏邮箱如下。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(viewModel.accounts) { account in
                    NavigationLink {
                        InboxView(viewModel: viewModel, account: account)
                    } label: {
                        AccountRow(account: account)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.99))
                }

                if viewModel.accountsHasMore {
                    Button {
                        Task { await viewModel.loadMoreAccounts() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMoreAccounts {
                                ProgressView()
                                    .controlSize(.small)
                                Text("加载中…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("加载更多账号")
                                    .font(.subheadline.weight(.medium))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .disabled(viewModel.isLoadingMoreAccounts)
                }
            } header: {
                if settings.mailUseExternalAPI {
                    Text("邮箱")
                }
            }

            if let error = viewModel.accountsError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.refreshAccounts()
        }
    }

    private var unconfiguredState: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                symbol: "envelope.badge.shield.half.filled",
                title: "未配置邮件服务",
                message: settings.mailUseExternalAPI
                    ? "请在设置中填写外部 API Key 与默认邮箱。"
                    : "请在设置中填写管理密码后返回此页。"
            )
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "无法加载账号",
                message: message
            )
            Button {
                Haptics.light()
                Task { await viewModel.refreshAccounts() }
            } label: {
                PrimaryButtonLabel(title: "重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

private struct AccountRow: View {
    let account: MailAccount

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.email)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let remark = account.remark, !remark.isEmpty {
                        Text(remark)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let status = account.status, !status.isEmpty {
                        Text(status)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("邮箱 \(account.email)")
    }
}

#Preview {
    AccountListView()
        .environmentObject(AppSettings.shared)
}
