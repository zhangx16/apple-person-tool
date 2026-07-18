import SwiftUI
import AVFoundation
import UIKit

// MARK: - Room ViewModel (play only — no danmaku)

@MainActor
final class LiveRoomViewModel: ObservableObject {
    let room: LiveRoomItem

    @Published var detail: LiveRoomDetail?
    @Published var qualities: [LivePlayQuality] = []
    @Published var selectedId: String?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published private(set) var player: AVPlayer?

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

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let d = try await LiveSiteRouter.roomDetail(platform: room.platform, roomId: room.roomId)
            guard !Task.isCancelled else { return }
            detail = d
            guard d.isLive else {
                errorMessage = "当前未开播"
                return
            }
            let qs = try await LiveSiteRouter.playQualities(detail: d)
            guard !Task.isCancelled else { return }
            qualities = qs
            guard let first = qs.first else {
                errorMessage = "无可用清晰度"
                return
            }
            selectedId = first.id
            await play(quality: first)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func selectQuality(_ q: LivePlayQuality) {
        selectedId = q.id
        Task { await play(quality: q) }
    }

    private func play(quality: LivePlayQuality) async {
        guard let detail else { return }
        do {
            let result = try await LiveSiteRouter.playURLs(detail: detail, quality: quality)
            guard !Task.isCancelled else { return }
            let ordered = result.urls.filter { URL(string: $0) != nil }.sorted { a, b in
                let am = a.contains(".m3u8")
                let bm = b.contains(".m3u8")
                if am != bm { return am && !bm }
                return false
            }
            guard let first = ordered.first, let url = URL(string: first) else {
                errorMessage = "无可用播放地址"
                return
            }
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": result.headers
            ])
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = p
            p.play()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
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
                .frame(height: 240)
                .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    infoArea
                    qualityPicker
                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let url = URL(string: vm.webFallback),
                       url.scheme == "http" || url.scheme == "https" {
                        Link("网页打开（备用）", destination: url)
                            .font(.footnote)
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
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var navTitle: String {
        if let name = vm.detail?.userName, !name.isEmpty { return name }
        if !room.userName.isEmpty { return room.userName }
        return "直播间"
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
                LivePlayerLayerView(player: player)
            } else if vm.isLoading {
                ProgressView().tint(.white)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.slash")
                        .foregroundStyle(.white.opacity(0.7))
                    if vm.errorMessage != nil {
                        Text("无法播放")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
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

// MARK: - AVPlayerLayer host

struct LivePlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            (layer as? AVPlayerLayer) ?? AVPlayerLayer()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
