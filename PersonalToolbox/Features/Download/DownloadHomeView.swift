import SwiftUI

/// Placeholder shell for the 下载 tab. Queue UI arrives in a later PR.
struct DownloadHomeView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                symbol: "arrow.down.circle",
                title: "暂无下载任务",
                message: "粘贴链接并开始下载后，任务队列将显示在这里。"
            )
            .background(AppleTheme.canvas)
            .navigationTitle("下载")
        }
    }
}

#Preview {
    DownloadHomeView()
}
