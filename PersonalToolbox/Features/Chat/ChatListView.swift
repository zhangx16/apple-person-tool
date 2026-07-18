import SwiftUI

/// Placeholder shell for the 助手 tab. Full list/thread UI arrives in a later PR.
struct ChatListView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "bubble.left.and.bubble.right",
                title: "开始一段新对话",
                message: "会话列表与流式对话将在后续版本接入。"
            )
            .background(AppleTheme.canvas)
            .navigationTitle("助手")
        }
    }
}

#Preview {
    ChatListView()
}
