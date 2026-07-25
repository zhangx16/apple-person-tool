import SwiftUI

struct HomeView: View {
    @Environment(NeteaseAPI.self) private var api

    @State private var phase: LoadingPhase = .loading
    @State private var recommended: [Playlist] = []
    @State private var albums: [Album] = []
    @State private var charts: [Playlist] = []
    @State private var artists: [Artist] = []
    @State private var reloadToken = 0

    private var remainingRecommendations: [Playlist] {
        Array(recommended.dropFirst(3))
    }

    var body: some View {
        Group {
            // Show shell as soon as load finished (even if some sections empty),
            // so static cards (每日推荐 / 新碟) remain usable when one API fails.
            if phase == .loaded || hasLoadedContent {
                content
            } else {
                initialState
            }
        }
        .navigationTitle("首页")
        // Inline title frees vertical space inside the toolbox tab.
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) {
            // Always reload on token change (includes first appear & 重试).
            await load()
        }
    }

    private var hasLoadedContent: Bool {
        !recommended.isEmpty || !albums.isEmpty || !charts.isEmpty || !artists.isEmpty
    }

    @ViewBuilder
    private var initialState: some View {
        switch phase {
        case .loading:
            ProgressView("正在为你挑选音乐")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ConnectionUnavailableView(message: message) {
                reloadToken += 1
            }
        case .loaded:
            ContentUnavailableView("暂无推荐", systemImage: "music.note.house")
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                featuredSection

                if !remainingRecommendations.isEmpty {
                    playlistSection(title: "为你推荐", playlists: remainingRecommendations)
                }

                if !charts.isEmpty {
                    playlistSection(title: "热门排行", playlists: charts, destination: .toplists)
                }

                if !albums.isEmpty {
                    albumSection
                }

                if !artists.isEmpty {
                    artistSection
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .refreshable {
            await load(showsInitialLoading: false)
        }
    }

    private var featuredSection: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                NavigationLink(value: MusicRoute.dailySongs) {
                    HomeEditorialCard(
                        eyebrow: "每日更新",
                        title: "每日推荐",
                        subtitle: "为你定制的歌曲",
                        systemImage: "calendar",
                        colors: [.pink, .red]
                    )
                }
                .homeFeaturedWidth()

                NavigationLink(value: MusicRoute.newAlbums) {
                    HomeEditorialCard(
                        eyebrow: "新鲜发行",
                        title: "新碟上架",
                        subtitle: "发现最近发布的专辑",
                        systemImage: "square.stack.fill",
                        colors: [.purple, .indigo]
                    )
                }
                .homeFeaturedWidth()

                ForEach(recommended.prefix(3)) { playlist in
                    NavigationLink(value: MusicRoute.playlist(playlist)) {
                        HomeFeaturedPlaylistCard(playlist: playlist)
                    }
                    .homeFeaturedWidth()
                    .musicMatchedTransitionSource(for: MusicRoute.playlist(playlist))
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private func playlistSection(
        title: String,
        playlists: [Playlist],
        destination: MusicRoute? = nil
    ) -> some View {
        HomeHorizontalSection(title: title, destination: destination) {
            ForEach(playlists) { playlist in
                NavigationLink(value: MusicRoute.playlist(playlist)) {
                    HomePlaylistCard(playlist: playlist)
                }
                .buttonStyle(.plain)
                .musicMatchedTransitionSource(for: MusicRoute.playlist(playlist))
            }
        }
    }

    private var albumSection: some View {
        HomeHorizontalSection(title: "新碟上架", destination: .newAlbums) {
            ForEach(albums) { album in
                NavigationLink(value: MusicRoute.album(album)) {
                    HomeAlbumCard(album: album)
                }
                .buttonStyle(.plain)
                .musicMatchedTransitionSource(for: MusicRoute.album(album))
            }
        }
    }

    private var artistSection: some View {
        HomeHorizontalSection(title: "热门歌手") {
            ForEach(artists) { artist in
                NavigationLink(value: MusicRoute.artist(artist.id)) {
                    HomeArtistCard(artist: artist)
                }
                .buttonStyle(.plain)
                .musicMatchedTransitionSource(for: MusicRoute.artist(artist.id))
            }
        }
    }

    private func load(showsInitialLoading: Bool = true) async {
        if showsInitialLoading, !hasLoadedContent {
            phase = .loading
        }

        do {
            // Soft-fail each section: eapi empty-body must not blank the whole home.
            async let loadedRecommended = try? api.recommendedPlaylists(limit: 12)
            async let loadedAlbums = try? api.newAlbums(limit: 10)
            async let loadedCharts = try? api.toplists()
            async let loadedArtists = try? api.topArtists()

            let (recommendations, albumsResult, chartsResult, artistsResult) = await (
                loadedRecommended,
                loadedAlbums,
                loadedCharts,
                loadedArtists
            )
            try Task.checkCancellation()

            recommended = recommendations ?? []
            albums = albumsResult ?? []
            charts = Array((chartsResult ?? []).prefix(10))
            artists = Array((artistsResult ?? []).prefix(10))

            if hasLoadedContent {
                phase = .loaded
            } else {
                // Absolute miss — surface retry, but keep message actionable.
                phase = .failed("网易云推荐接口暂时无响应（可能是网络或地区限制）。可点重试，或先用搜索 / Navidrome。")
            }
        } catch is CancellationError {
            return
        } catch {
            if hasLoadedContent {
                // Keep previous content on pull-to-refresh failure.
                phase = .loaded
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

private extension View {
    func homeFeaturedWidth() -> some View {
        containerRelativeFrame(.horizontal) { length, _ in
            // Slightly narrower cards so more content fits on screen.
            length * 0.72
        }
        .buttonStyle(.plain)
    }
}
