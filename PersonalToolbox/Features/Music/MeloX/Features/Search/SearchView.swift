import SwiftUI

struct SearchView: View {
    @Environment(NeteaseAPI.self) private var api
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(MeloXSettings.self) private var settings

    @State private var query = ""
    @State private var scope: SearchKind = .songs
    @State private var catalogScope: SearchCatalogScope = .netease
    @State private var phase: LoadingPhase = .loaded
    @State private var songs: [Song] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var playlists: [Playlist] = []
    @State private var appleMusicResults: [AppleMusicCandidate] = []
    @State private var completedRequest: SearchRequest?

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                SearchDiscoveryView()
            } else {
                searchResults
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: catalogScope == .appleMusic
                ? "在 Apple Music 曲库搜索"
                : "歌曲、歌手、专辑或歌单"
        )
        .toolbar {
            if !trimmedQuery.isEmpty, scope == .songs || catalogScope == .appleMusic {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("曲库", selection: $catalogScope) {
                        Text("网易云").tag(SearchCatalogScope.netease)
                        Text("Apple Music").tag(SearchCatalogScope.appleMusic)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
        .searchScopes($scope) {
            ForEach(SearchKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .onChange(of: catalogScope) { _, _ in
            completedRequest = nil
        }
        .onAppear {
            if let raw = AppDeepLinkStore.shared.consumeMusicURL() {
                // Prefer numeric id as search query; else full URL (user can refine).
                if let idRange = raw.range(of: #"[?&]id=(\d+)"#, options: .regularExpression),
                   let num = raw[idRange].split(separator: "=").last {
                    query = String(num)
                } else {
                    query = raw
                }
            }
        }
        .overlay {
            if !trimmedQuery.isEmpty, case .failed(let message) = phase {
                ContentUnavailableView(
                    "搜索失败",
                    systemImage: "exclamationmark.magnifyingglass",
                    description: Text(message)
                )
            } else if !trimmedQuery.isEmpty, phase == .loaded, resultIsEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .alert(
            "收藏失败",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.clearError() } }
            )
        ) {
            Button("好", role: .cancel) {
                library.clearError()
            }
        } message: {
            Text(library.errorMessage ?? "未知错误")
        }
        .task(id: SearchRequest(query: query, kind: scope, catalog: catalogScope)) {
            let request = SearchRequest(query: query, kind: scope, catalog: catalogScope)
            guard completedRequest != request else { return }
            await search(request)
        }
    }

    private var searchResults: some View {
        List {
            if phase == .loading {
                HStack {
                    Spacer()
                    ProgressView("搜索中")
                    Spacer()
                }
            }

            if catalogScope == .appleMusic {
                Section {
                    ForEach(appleMusicResults) { candidate in
                        Button {
                            Task { await playAppleMusicSearchResult(candidate) }
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkImage(url: candidate.artworkURL, cornerRadius: 7)
                                    .frame(width: 54, height: 54)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(candidate.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(.pink)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Apple Music 曲库")
                } footer: {
                    Text("直接 MusicKit 真播放，不经过网易云。")
                }
            } else {
            switch scope {
            case .songs:
                ForEach(displayedSongs) { song in
                    Button {
                        Task { await player.play(song, in: displayedSongs) }
                    } label: {
                        TrackRowView(song: song, showsArtwork: true, queueContext: displayedSongs)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button {
                            library.toggle(song: song)
                        } label: {
                            Label(
                                library.contains(song: song) ? "取消收藏" : "收藏",
                                systemImage: library.contains(song: song) ? "heart.slash" : "heart"
                            )
                        }
                        .tint(.pink)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task {
                                await player.playViaAppleMusic(
                                    song: song,
                                    in: displayedSongs
                                )
                            }
                        } label: {
                            Label("Apple Music", systemImage: "apple.logo")
                        }
                        .tint(.pink)
                    }
                }
            case .albums:
                ForEach(albums) { album in
                    NavigationLink(value: MusicRoute.album(album)) {
                        SearchMediaRow(
                            title: album.name,
                            subtitle: album.artistText,
                            artworkURL: album.artworkURL,
                            circular: false
                        )
                    }
                    .musicMatchedTransitionSource(for: MusicRoute.album(album))
                }
            case .artists:
                ForEach(artists) { artist in
                    NavigationLink(value: MusicRoute.artist(artist.id)) {
                        SearchMediaRow(
                            title: artist.name,
                            subtitle: artist.aliases.first,
                            artworkURL: artist.artworkURL,
                            circular: true
                        )
                    }
                    .musicMatchedTransitionSource(for: MusicRoute.artist(artist.id))
                }
            case .playlists:
                ForEach(playlists) { playlist in
                    NavigationLink(value: MusicRoute.playlist(playlist)) {
                        SearchMediaRow(
                            title: playlist.name,
                            subtitle: "\(playlist.trackCount) 首歌曲",
                            artworkURL: playlist.artworkURL,
                            circular: false
                        )
                    }
                    .musicMatchedTransitionSource(for: MusicRoute.playlist(playlist))
                }
            }
            } // end netease catalog
        }
        .listStyle(.plain)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedSongs: [Song] {
        if settings.hideLikelyIncompleteTracks {
            return songs.filter { !$0.isLikelyIncompleteWithoutVIP }
        }
        return songs
    }

    private var resultIsEmpty: Bool {
        if catalogScope == .appleMusic {
            return appleMusicResults.isEmpty
        }
        switch scope {
        case .songs: return displayedSongs.isEmpty
        case .albums: return albums.isEmpty
        case .artists: return artists.isEmpty
        case .playlists: return playlists.isEmpty
        }
    }

    private func search(_ request: SearchRequest) async {
        let keywords = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywords.isEmpty else {
            clearResults()
            phase = .loaded
            completedRequest = request
            return
        }
        phase = .loading
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        if catalogScope == .appleMusic {
            do {
                appleMusicResults = try await AppleMusicBridge.shared.searchCatalog(query: keywords)
                songs = []
                albums = []
                artists = []
                playlists = []
                phase = .loaded
                completedRequest = request
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
            }
            return
        }

        do {
            let result = try await api.search(keywords, kind: request.kind)
            guard !Task.isCancelled else { return }
            songs = result.songs ?? []
            albums = result.albums ?? []
            artists = result.artists ?? []
            playlists = result.playlists ?? []
            appleMusicResults = []

            if request.kind == .songs, !songs.isEmpty {
                let details = try? await api.songDetails(ids: songs.map(\.id))
                guard !Task.isCancelled else { return }
                if let details, !details.isEmpty {
                    songs = details
                }
            }
            phase = .loaded
            completedRequest = request
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func playAppleMusicSearchResult(_ candidate: AppleMusicCandidate) async {
        await player.playAppleMusicCatalogCandidate(candidate)
    }

    private func clearResults() {
        songs = []
        albums = []
        artists = []
        playlists = []
        appleMusicResults = []
    }
}

private enum SearchCatalogScope: Hashable {
    case netease
    case appleMusic
}

private struct SearchRequest: Hashable {
    let query: String
    let kind: SearchKind
    let catalog: SearchCatalogScope
}

private struct SearchMediaRow: View {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let circular: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: artworkURL, cornerRadius: circular ? 1_000 : 7)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
