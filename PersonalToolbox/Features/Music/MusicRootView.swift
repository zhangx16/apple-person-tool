import SwiftUI
import WebKit

/// 音乐 Tab：MeloX 全量源码已入库，但 CI（Xcode 15.4）无法编译 iOS 26 API。
/// 当前提供可运行的网易云 H5 壳 + 说明；完整原生 MeloX 需 Xcode 16+ 再开编译。
struct MusicRootView: View {
    @State private var path = NavigationPath()
    @State private var showAbout = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                NeteaseMusicWebView(url: URL(string: "https://music.163.com/m")!)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("音乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("关于音乐模块")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Link(destination: URL(string: "https://music.163.com")!) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("系统浏览器打开")
                }
            }
            .sheet(isPresented: $showAbout) {
                NavigationStack {
                    List {
                        Section("来源") {
                            Text("基于开源项目 MeloX（youshen2/MeloX）接入计划。")
                            Link("MeloX 仓库", destination: URL(string: "https://github.com/youshen2/MeloX")!)
                        }
                        Section("当前构建") {
                            Text("因 CI 使用 Xcode 15.4 / iOS 17 SDK，无法编译 MeloX 上游 iOS 26 专用 API。")
                            Text("本页先用网易云官方 H5 提供可用听歌入口；完整原生 UI/播放器源码已在 Features/Music/MeloX/。")
                        }
                        Section("说明") {
                            Text("非官方客户端，与网易云音乐无隶属关系。")
                        }
                    }
                    .navigationTitle("关于")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showAbout = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

private struct NeteaseMusicWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
