import SwiftUI
import SafariServices
import UIKit
import ObjectiveC

/// B站直播进房页：进程外 Safari 播放。
///
/// 历史多次硬崩均与应用内链路相关（MobileVLCKit / AVPlayer 拉流 / 页内 WKWebView 加载
/// live.bilibili.com H5）。`SFSafariViewController` 跑在独立进程，页面/解码异常不会拖垮 App。
struct BilibiliLiveWebRoomView: View {
    let room: LiveRoomItem
    @Environment(\.dismiss) private var dismiss

    @State private var titleText: String = ""
    @State private var subtitleText: String = ""
    @State private var statusText: String = "准备打开…"
    @State private var isLive: Bool?
    @State private var loadError: String?
    @State private var didAutoOpen = false

    private var pageURL: URL {
        Self.h5URL(roomId: room.roomId)
    }

    /// 稳定的 H5 房间地址（纯数字 roomId；非法时回退首页）。
    static func h5URL(roomId: String) -> URL {
        let raw = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let rid = raw.filter(\.isNumber)
        if !rid.isEmpty, let u = URL(string: "https://live.bilibili.com/h5/\(rid)") {
            return u
        }
        if !raw.isEmpty,
           let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let u = URL(string: "https://live.bilibili.com/h5/\(encoded)") {
            return u
        }
        return URL(string: "https://live.bilibili.com")!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                infoCard
                actionCard
                tipCard
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { dismiss() }
            }
        }
        // 不在 body 里同步创建任何 Web/播放器视图（WKWebView / VLC 均已移除）。
        .onAppear {
            // 等 present 动画结束后再打开 Safari，避免转场竞态。
            statusText = "即将打开直播页…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard !didAutoOpen else { return }
                didAutoOpen = true
                openSafari()
            }
        }
        .task {
            // 延后网络：失败只影响标题，绝不阻塞进房。
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshMeta()
        }
    }

    private var navTitle: String {
        let n = subtitleText.isEmpty ? room.userName : subtitleText
        return n.isEmpty ? "B站直播" : n
    }

    // MARK: - Sections

    private var headerCard: some View {
        HStack(spacing: 12) {
            LivePlatformMark(platform: .bilibili, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("B站直播")
                    .font(.headline)
                HStack(spacing: 8) {
                    if let isLive {
                        Text(isLive ? "直播中" : "未开播")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isLive ? Color.red : Color.gray, in: Capsule())
                    }
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayTitle)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if !displayName.isEmpty {
                Text(displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("房间号 \(room.roomId)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let loadError, !loadError.isEmpty {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            Button {
                openSafari()
            } label: {
                Label("打开直播（安全模式）", systemImage: "play.rectangle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(LiveUI.brand(.bilibili).brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())

            HStack(spacing: 10) {
                Button {
                    UIApplication.shared.open(pageURL)
                    statusText = "已交给系统浏览器"
                } label: {
                    Label("系统浏览器", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button {
                    UIPasteboard.general.string = pageURL.absoluteString
                    statusText = "链接已复制"
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tipCard: some View {
        Text("B站直播在独立 Safari 页播放，避免应用内解码/网页内核闪退。关闭播放页可回到本页重新打开。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var displayTitle: String {
        if !titleText.isEmpty { return titleText }
        if !room.title.isEmpty { return room.title }
        return "房间 \(room.roomId)"
    }

    private var displayName: String {
        if !subtitleText.isEmpty { return subtitleText }
        return room.userName
    }

    // MARK: - Actions

    private func openSafari() {
        statusText = "打开直播页…"
        BilibiliSafariPresenter.present(url: pageURL) {
            statusText = "已返回 · 可再次打开"
        }
    }

    private func refreshMeta() async {
        let rid = room.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return }
        do {
            let detail = try await BilibiliLiveService.shared.getRoomDetail(roomId: rid)
            await MainActor.run {
                titleText = detail.title
                subtitleText = detail.userName
                isLive = detail.isLive
                if !(statusText.hasPrefix("打开") || statusText.hasPrefix("即将")) {
                    statusText = detail.isLive ? "可播放" : "未开播 · 仍可打开页面"
                }
                loadError = nil
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Out-of-process Safari presenter

/// 从当前最顶层 VC present `SFSafariViewController`（不嵌套 SwiftUI fullScreenCover）。
enum BilibiliSafariPresenter {
    @MainActor
    static func present(url: URL, onFinish: (() -> Void)? = nil) {
        guard let host = topViewController() else {
            UIApplication.shared.open(url)
            return
        }
        // 已在播 Safari 时不重复堆叠。
        if host is SFSafariViewController { return }
        if host.presentedViewController is SFSafariViewController { return }

        let safari = SFSafariViewController(url: url)
        safari.dismissButtonStyle = .close
        safari.preferredControlTintColor = UIColor(red: 0, green: 0.63, blue: 0.84, alpha: 1)
        let proxy = SafariDismissProxy(onFinish: onFinish)
        safari.delegate = proxy
        // Retain proxy for the lifetime of the safari VC.
        objc_setAssociatedObject(
            safari,
            &SafariDismissProxy.assocKey,
            proxy,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        host.present(safari, animated: true)
    }

    @MainActor
    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController?
        if let base {
            root = base
        } else {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                ?? scenes.flatMap(\.windows).first
            root = window?.rootViewController
        }
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}

private final class SafariDismissProxy: NSObject, SFSafariViewControllerDelegate {
    static var assocKey: UInt8 = 0
    let onFinish: (() -> Void)?

    init(onFinish: (() -> Void)?) {
        self.onFinish = onFinish
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        onFinish?()
    }
}
