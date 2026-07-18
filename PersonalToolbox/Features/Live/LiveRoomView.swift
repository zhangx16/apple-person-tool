import SwiftUI
import AVFoundation
import UIKit

// MARK: - Room ViewModel

@MainActor
final class LiveRoomViewModel: ObservableObject {
    let room: LiveRoomItem

    @Published var detail: LiveRoomDetail?
    @Published var qualities: [LivePlayQuality] = []
    @Published var selectedId: String?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var showDanmaku = true
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
    @StateObject private var danmaku = LiveDanmakuService()

    init(room: LiveRoomItem) {
        self.room = room
        _vm = StateObject(wrappedValue: LiveRoomViewModel(room: room))
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
                .frame(height: 220)
                .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if vm.showDanmaku {
                        danmakuPanel
                    }
                    infoArea
                    qualityPicker
                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
                HStack(spacing: 12) {
                    Button {
                        vm.showDanmaku.toggle()
                        danmaku.isEnabled = vm.showDanmaku
                        if vm.showDanmaku, let d = vm.detail {
                            softStartDanmaku(d)
                        } else {
                            danmaku.stop()
                        }
                    } label: {
                        Image(systemName: vm.showDanmaku ? "text.bubble.fill" : "text.bubble")
                    }
                    if let url = URL(string: vm.detail?.webURL ?? vm.webFallback),
                       url.scheme == "http" || url.scheme == "https" {
                        Link(destination: url) {
                            Image(systemName: "safari")
                        }
                    }
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear {
            danmaku.stop()
            vm.stop()
        }
        .onChange(of: vm.detail?.roomId) { _, _ in
            if vm.showDanmaku, let d = vm.detail, d.isLive {
                softStartDanmaku(d)
            }
        }
    }

    private var navTitle: String {
        if let name = vm.detail?.userName, !name.isEmpty { return name }
        return room.userName.isEmpty ? "直播间" : room.userName
    }

    private func softStartDanmaku(_ d: LiveRoomDetail) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard vm.showDanmaku else { return }
            danmaku.start(platform: room.platform, danmakuJSON: d.danmakuJSON, roomId: d.roomId)
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
                Image(systemName: "play.slash")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var danmakuPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("弹幕")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(danmaku.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(danmaku.messages) { msg in
                            HStack(alignment: .top, spacing: 4) {
                                Text(msg.userName.isEmpty ? "用户" : msg.userName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(safeColor(msg.colorHex))
                                Text(msg.text)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                            .id(msg.id)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: danmaku.messages.count) { _, _ in
                    if let last = danmaku.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func safeColor(_ hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.detail?.title ?? room.title)
                .font(.headline)
            HStack {
                Text(vm.detail?.userName ?? room.userName)
                Spacer()
                if let d = vm.detail {
                    Text(d.isLive ? "直播中" : "未开播")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d.isLive ? Color.green : Color.secondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let intro = vm.detail?.introduction, !intro.isEmpty {
                Text(intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
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

// MARK: - AVPlayerLayer host (no AVPlayerViewController)

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
            // layerClass guarantees type
            layer as? AVPlayerLayer ?? AVPlayerLayer()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
