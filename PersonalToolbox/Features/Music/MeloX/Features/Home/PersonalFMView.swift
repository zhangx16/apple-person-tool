import SwiftUI

/// 网易云私人 FM。队列由服务端分批推荐，当前批次耗尽时自动续取。
struct PersonalFMView: View {
    @Environment(NeteaseAPI.self) private var api
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library

    @State private var recommendations: [Song] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsLogin = false

    private var current: Song? {
        guard recommendations.contains(where: { $0.id == player.currentSong?.id }) else { return nil }
        return player.currentSong
    }

    var body: some View {
        ZStack {
            NowPlayingBackground(artworkURL: current?.album?.artworkURL)

            if library.isLoggedIn {
                playerContent
            } else {
                loginPrompt
            }
        }
        .navigationTitle("私人漫游")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsLogin) {
            NavigationStack { NeteaseLoginView() }
        }
        .alert("私人漫游暂不可用", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private var playerContent: some View {
        VStack(spacing: 24) {
            Spacer()

            ArtworkImage(url: current?.album?.artworkURL, cornerRadius: 20)
                .frame(maxWidth: 330, maxHeight: 330)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
                .scaleEffect(player.isPlaying && current != nil ? 1 : 0.94)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: player.isPlaying)

            VStack(spacing: 6) {
                Text(current?.name ?? "私人漫游")
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(current?.artistText ?? "根据你的口味推荐音乐")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if current == nil {
                Button { Task { await start() } } label: {
                    if isLoading {
                        ProgressView().frame(minWidth: 120)
                    } else {
                        Label("开始漫游", systemImage: "wave.3.right")
                            .frame(minWidth: 120)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isLoading)
            } else {
                controls
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { Task { await discardCurrent() } } label: {
                Image(systemName: "trash")
                    .frame(width: 48, height: 48)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("不喜欢")

            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(Color.red.gradient, in: Circle())
            }
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Button { Task { await next() } } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 48, height: 48)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("下一首")
        }
        .buttonStyle(.plain)
    }

    private var loginPrompt: some View {
        ContentUnavailableView {
            Label("登录后开启私人漫游", systemImage: "wave.3.right.circle")
        } description: {
            Text("网易云会根据你的听歌口味持续推荐歌曲")
        } actions: {
            Button("登录网易云音乐") { showsLogin = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func start() async {
        isLoading = true
        defer { isLoading = false }
        do {
            recommendations = try await api.personalFM()
            guard let first = recommendations.first else {
                throw APIError.noPlayableSource
            }
            await player.play(first, in: recommendations)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func next() async {
        if player.canPlayNext {
            await player.next()
            return
        }
        await start()
    }

    private func discardCurrent() async {
        guard let song = current else { return }
        do {
            try await api.discardFromPersonalFM(id: song.id)
            recommendations.removeAll { $0.id == song.id }
            if let nextSong = recommendations.first {
                await player.play(nextSong, in: recommendations)
            } else {
                await start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
