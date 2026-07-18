import SwiftUI

/// Placeholder shell for the 邮件 tab. Accounts/inbox arrive in a later PR.
struct AccountListView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "envelope",
                title: "暂无邮箱",
                message: "在设置中配置邮件服务后，账号与收件箱将显示在这里。"
            )
            .background(AppleTheme.canvas)
            .navigationTitle("邮件")
        }
    }
}

#Preview {
    AccountListView()
}
