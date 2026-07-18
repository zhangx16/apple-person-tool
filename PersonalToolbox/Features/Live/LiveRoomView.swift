import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - Room ViewModel

@MainActor
final class LiveRoomViewModel: ObservableObject {
    let room: LiveRoomItem

    @Published var detail: LiveRoomDetail?
    @Published var qualities: [LivePlayQuality] = []
    @Published var selectedId: String?
    @Published var isLoading = true
    @Published var statusText: String = "正在连接…"
    @Published var errorMessage: String?
    @Published private(set) var player: AVPlayer?
    @Published var lastPlayURL: String?

    private var loadTask: Task<Void, Never>?

    init(room: LiveRoomItem) {
        self.room = room
    }

    func start() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    func retry() {
        start()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        statusText = "获取房间信息…"
        defer { isLoading = false }

        do {
            let d = try await LiveSiteRouter.roomDetail(platform: room.platform, roomId: room.roomId)
            guard !Task.isCancelled else { return }
            detail = d
            statusText = d.isLive ? "解析播放地址…" : "主播未开播"
            guard d.isLive else {
                errorMessage = "当前未开播，可点下方网页打开"
                return
            }
            let qs = try await LiveSiteRouter.playQualities(detail: d)
            guard !Task.isCancelled else { return }
            qualities = qs
            guard let first = qs.first else {
                errorMessage = "无可用清晰度，可点下方网页打开"
                return
            }
            selectedId = first.id
            await play(quality: first)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            statusText = "加载失败"
        }
    }

    func selectQuality(_ q: LivePlayQuality) {
        selectedId = q.id
        Task { await play(quality: q) }
    }

    private func play(quality: LivePlayQuality) async {
        guard let detail else { return }
        statusText = "拉取线路 \(quality.name)…"
        do {
            let result = try await LiveSiteRouter.playURLs(detail: detail, quality: quality)
            guard !Task.isCancelled else { return }

            // Prefer HLS for AVPlayer stability; keep others as fallback.
            var candidates = result.urls.filter { URL(string: $0) != nil }
            candidates.sort { a, b in
                let am = a.contains(".m3u8")
                let bm = b.contains(".m3u8")
                if am != bm { return am && !bm }
                // Prefer non-mcdn
                let amd = a.contains("mcdn")
                let bmd = b.contains("mcdn")
                if amd != bmd { return !amd && bmd }
                return false
            }
            guard !candidates.isEmpty else {
                errorMessage = "无可用播放地址，可点下方网页打开"
                statusText = "无地址"
                return
            }

            var lastError: String?
            for urlString in candidates.prefix(4) {
                guard let url = URL(string: urlString) else { continue }
                statusText = "尝试播放…"
                let ok = await startPlayer(url: url, headers: result.headers)
                if ok {
                    lastPlayURL = urlString
                    errorMessage = nil
                    statusText = "播放中 · \(quality.name)"
                    return
                }
                lastError = "线路失败"
            }
            errorMessage = lastError ?? "播放失败，可点下方网页打开"
            statusText = "播放失败"
            player = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            statusText = "拉流失败"
        }
    }

    /// Returns true if item seems ready (or at least was created without immediate fail).
    private func startPlayer(url: URL, headers: [String: String]) async -> Bool {
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers
        ])
        // Soft check load — don't block forever.
        let playable: Bool = await withCheckedContinuation { cont in
            asset.loadValuesAsynchronously(forKeys: ["playable", "tracks"]) {
                var err: NSError?
                let status = asset.statusOfValue(forKey: "playable", error: &err)
                cont.resume(returning: status == .loaded || status == .unknown)
            }
        }
        if !playable {
            return false
        }
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = p
        p.play()
        return true
    }

    var webFallback: String {
        if let web = detail?.webURL, !web.isEmpty { return web }
        switch room.platform {
        case .bilibili: return "https://live.bilibili.com/\(room.roomId)"
        case .huya: return "https://www.huya.com/\(room.roomId)"
        case .douyu: return "https://www.douyu.com/\(room.roomId)"
        case .douyin: return "https://live.douyin.com/\(room.roomId)"
        case .kuaishou: return "https://live.kuaishou.com/u/\(room.roomId)"
        }
    }
}

// MARK: - Room UI

struct LiveRoomView: View {
    let room: LiveRoomItem
    @StateObject private var vm: LiveRoomViewModel
    @ObservedObject private var follows = LiveFollowStore.shared

    init(room: LiveRoomItem) {
        self.room = room
        _vm = StateObject(wrappedValue: LiveRoomViewModel(room: room))
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
                .frame(minHeight: 220, maxHeight: 280)
                .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    infoArea
                    qualityPicker

                    Text(vm.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                        Button("重试原生播放") { vm.retry() }
                            .buttonStyle(.bordered)
                    }

                    if let url = URL(string: vm.webFallback),
                       url.scheme == "http" || url.scheme == "https" {
                        Link(destination: url) {
                            Label("网页打开（备用）", systemImage: "safari")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFollow()
                } label: {
                    Image(systemName: isFollowed ? "star.fill" : "star")
                        .foregroundStyle(isFollowed ? Color.yellow : Color.primary)
                }
                .accessibilityLabel(isFollowed ? "取消关注" : "关注")
            }
        }
        .task {
            // Prefer .task over onAppear — tied to view lifetime, more reliable in sheets.
            vm.start()
        }
        .onDisappear {
            vm.stop()
        }
    }

    private var navTitle: String {
        if let name = vm.detail?.userName, !name.isEmpty { return name }
        if !room.userName.isEmpty { return room.userName }
        return "直播间 \(room.roomId)"
    }

    private var isFollowed: Bool {
        let rid = vm.detail?.roomId ?? room.roomId
        let p = vm.detail?.platform ?? room.platform
        return follows.isFollowing(platform: p, roomId: rid)
    }

    private func toggleFollow() {
        let item = LiveRoomItem(
            platform: vm.detail?.platform ?? room.platform,
            roomId: vm.detail?.roomId ?? room.roomId,
            title: vm.detail?.title ?? room.title,
            cover: vm.detail?.cover ?? room.cover,
            userName: vm.detail?.userName ?? room.userName,
            online: vm.detail?.online ?? room.online
        )
        if isFollowed {
            follows.unfollow(platform: item.platform, roomId: item.roomId)
        } else {
            follows.follow(item)
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        ZStack {
            Color.black
            if let player = vm.player {
                // VideoPlayer is more reliable than raw layer for HLS on device.
                VideoPlayer(player: player)
            } else if vm.isLoading {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(vm.statusText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.slash")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(vm.errorMessage ?? "暂无画面")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.detail?.title ?? (room.title.isEmpty ? "直播间 \(room.roomId)" : room.title))
                .font(.headline)
            HStack {
                Text(vm.detail?.userName ?? (room.userName.isEmpty ? platformTitle : room.userName))
                Spacer()
                if let d = vm.detail {
                    Text(d.isLive ? "直播中" : "未开播")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d.isLive ? Color.green : Color.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("\(platformTitle) · 房间 \(vm.detail?.roomId ?? room.roomId)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var platformTitle: String {
        (vm.detail?.platform ?? room.platform).title
    }

    @ViewBuilder
    private var qualityPicker: some View {
        if !vm.qualities.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(vm.qualities) { q in
                        Button {
                            vm.selectQuality(q)
                        } label: {
                            Text(q.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(vm.selectedId == q.id ? Color.white : Color.primary)
                                .background(
                                    vm.selectedId == q.id ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
