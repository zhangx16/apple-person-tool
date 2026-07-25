import SwiftUI
import UIKit

/// Floating smart action when the system pasteboard has recognizable content.
struct ClipboardSmartBar: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var deepLink = AppDeepLinkStore.shared

    @State private var hit: ClipboardSmartHit?
    @State private var lastFingerprint = ""
    @State private var toast: String?

    /// Cooldown map: fingerprint → last shown date (UserDefaults).
    private static let cooldownKey = "clipboardSmart.cooldown.v1"
    private static let cooldownSeconds: TimeInterval = 600 // 10 minutes

    var body: some View {
        VStack(spacing: 0) {
            if let hit {
                bar(hit)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
            if let toast {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .animation(AppleTheme.preferredSnappy, value: hit?.id)
        .onAppear { refreshFromPasteboard() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshFromPasteboard()
        }
        .onChange(of: selectedTab) { _, _ in
            refreshFromPasteboard()
        }
    }

    private func bar(_ hit: ClipboardSmartHit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: hit.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: hit.tintHex).brandGradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(hit.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                Button("打开") { act(hit) }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(hex: hit.tintHex).brandGradient, in: Capsule())

                Button {
                    withAnimation { self.hit = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Button("10 分钟不再提示") {
                    markCooldown(for: hit)
                    withAnimation { self.hit = nil }
                    flash("已冷却 10 分钟")
                }
                .font(.caption2.weight(.semibold))
                Button("不再提示此类") {
                    muteKind(hit.kind)
                    withAnimation { self.hit = nil }
                    flash("已静音「\(hit.title)」类")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppStroke.highlight, lineWidth: 1)
        }
        .modifier(AppShadow.mid())
    }

    private func refreshFromPasteboard() {
        guard settings.clipboardSmartBarEnabled else {
            hit = nil
            return
        }
        let raw = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            hit = nil
            return
        }
        let fp = String(raw.prefix(240))
        // Same paste content: only re-show if fingerprint changed.
        if fp == lastFingerprint, hit != nil { return }
        lastFingerprint = fp

        guard let detected = ClipboardSmartRouter.detect(raw) else {
            hit = nil
            return
        }
        if settings.clipboardMutedKinds.contains(detected.kind.rawValue) {
            hit = nil
            return
        }
        if isInCooldown(fingerprint: fp) {
            hit = nil
            return
        }
        hit = detected
    }

    private func act(_ hit: ClipboardSmartHit) {
        markCooldown(for: hit)
        switch hit.kind {
        case .liveRoom:
            let parts = hit.payload.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2, let p = LivePlatform(rawValue: parts[0]) {
                deepLink.openLive(platform: p, roomId: parts[1])
                flash("正在打开直播间")
            } else {
                selectedTab = .live
            }
        case .musicNetease:
            deepLink.openMusic(url: hit.payload)
            flash("已切换到音乐 · 可在搜索粘贴链接")
        case .videoDownload:
            WatchLaterStore.shared.add(url: hit.payload, title: "剪贴板视频", source: "clipboard")
            deepLink.openDownload(url: hit.payload)
            flash("已填入下载并加入稍后再看")
        case .ipAddress:
            deepLink.openIP(hit.payload)
            flash("打开 IP 检测")
        case .expressTracking:
            ExpressService.shared.add(trackingNo: hit.payload)
            deepLink.openExpress(hit.payload)
            flash("已添加快递单号")
        case .subscriptionURL:
            deepLink.presentSheet = .proxyPack
            flash("节点 / 订阅相关 · 打开节点探测包")
        case .genericURL:
            if let url = URL(string: hit.payload) {
                UIApplication.shared.open(url)
            }
        }
        withAnimation { self.hit = nil }
    }

    private func muteKind(_ kind: ClipboardSmartKind) {
        var list = settings.clipboardMutedKinds
        if !list.contains(kind.rawValue) {
            list.append(kind.rawValue)
            settings.clipboardMutedKinds = list
        }
    }

    private func markCooldown(for hit: ClipboardSmartHit) {
        var map = UserDefaults.standard.dictionary(forKey: Self.cooldownKey) as? [String: Double] ?? [:]
        let fp = String(hit.payload.prefix(240))
        map[fp] = Date().timeIntervalSince1970
        // prune old
        let now = Date().timeIntervalSince1970
        map = map.filter { now - $0.value < Self.cooldownSeconds * 3 }
        UserDefaults.standard.set(map, forKey: Self.cooldownKey)
    }

    private func isInCooldown(fingerprint: String) -> Bool {
        let map = UserDefaults.standard.dictionary(forKey: Self.cooldownKey) as? [String: Double] ?? [:]
        guard let t = map[fingerprint] else { return false }
        return Date().timeIntervalSince1970 - t < Self.cooldownSeconds
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                if toast == text { toast = nil }
            }
        }
    }
}
