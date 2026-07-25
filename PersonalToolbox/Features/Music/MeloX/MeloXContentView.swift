import SwiftUI

/// Native MeloX experience embedded in PersonalToolbox.
///
/// Section switching lives in a **bottom** module bar (above the app tab bar),
/// so content pages keep a clean top navigation title — no top segment strip.
struct MeloXContentView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(MeloXSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads

    @State private var selectedTab: MeloXTab
    @State private var homePath = NavigationPath()
    @State private var explorePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var playerPresentation: PlayerPresentation?
    @State private var neteaseSharePresentation: NeteaseSharePresentation?
    @State private var nowPlayingSharePresentation: NeteaseSharePresentation?
    @State private var pendingMusicRoute: MusicRoute?
    @Namespace private var musicNavigationNamespace

    init(initialTab: MeloXTab = .home) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                mainExperience
            } else {
                OnboardingView()
            }
        }
    }

    private var mainExperience: some View {
        sectionStack
            .environment(\.musicNavigationNamespace, musicNavigationNamespace)
            // Bottom chrome: mini player + section tabs. Content uses full top for nav titles.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
            .environment(\.openMusicRoute, OpenMusicRouteAction(action: openMusicRoute))
            .environment(\.openNeteaseShare, OpenNeteaseShareAction(action: openNeteaseShare))
            .fullScreenCover(item: $playerPresentation, onDismiss: finishPendingSongNavigation) { destination in
                switch destination {
                case .nowPlaying:
                    NowPlayingView(initialPage: initialNowPlayingPage)
                        .environment(\.openMusicRoute, OpenMusicRouteAction(action: openMusicRoute))
                        .environment(
                            \.openNeteaseShare,
                            OpenNeteaseShareAction { presentation in
                                presentNeteaseShare(presentation, fromNowPlaying: true)
                            }
                        )
                        .sheet(item: $nowPlayingSharePresentation) { presentation in
                            NeteaseShareSheet(presentation: presentation)
                        }
                }
            }
            .sheet(item: $neteaseSharePresentation) { presentation in
                NeteaseShareSheet(presentation: presentation)
            }
            .task { await player.restore() }
            .task(id: settings.cookie) { await library.refresh() }
            .onChange(of: selectedTab) { _, tab in
                settings.lastSelectedTab = tab
            }
            .alert(
                "歌曲无法播放",
                isPresented: Binding(
                    get: { player.playbackIssue != nil },
                    set: { if !$0 { player.dismissPlaybackIssue() } }
                )
            ) {
                if player.canPlayNext {
                    Button("播放下一首") {
                        player.dismissPlaybackIssue()
                        Task { await player.next() }
                    }
                }
                Button("好", role: .cancel) { player.dismissPlaybackIssue() }
            } message: {
                Text(player.playbackIssue?.message ?? "当前歌曲暂时无法播放。")
            }
            .alert(
                "下载操作失败",
                isPresented: Binding(
                    get: { downloads.errorMessage != nil },
                    set: { if !$0 { downloads.clearError() } }
                )
            ) {
                Button("好", role: .cancel) { downloads.clearError() }
            } message: {
                Text(downloads.errorMessage ?? "无法完成下载操作。")
            }
            .appLaunchExperience()
    }

    /// Mini player (if any) + compact section icons.
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            if player.currentSong != nil {
                MiniPlayerView {
                    playerPresentation = .nowPlaying
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            musicSectionBar
        }
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.snappy(duration: 0.28), value: player.currentSong?.id)
    }

    /// Icon + short label row — sits above the app’s own tab bar.
    private var musicSectionBar: some View {
        HStack(spacing: 0) {
            ForEach(MeloXTab.allCases) { tab in
                let on = selectedTab == tab
                Button {
                    // Double-tap same tab pops to root of that stack.
                    if selectedTab == tab {
                        popToRoot(tab)
                    } else {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: on ? .semibold : .regular))
                            .symbolVariant(on ? .fill : .none)
                        Text(tab.title)
                            .font(.system(size: 10, weight: on ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var sectionStack: some View {
        switch selectedTab {
        case .home:
            NavigationStack(path: $homePath) {
                HomeView()
                    .musicDestinations(in: musicNavigationNamespace)
            }
        case .explore:
            NavigationStack(path: $explorePath) {
                ExploreView()
                    .musicDestinations(in: musicNavigationNamespace)
            }
        case .library:
            NavigationStack(path: $libraryPath) {
                LibraryView()
                    .musicDestinations(in: musicNavigationNamespace)
            }
        case .search:
            NavigationStack(path: $searchPath) {
                SearchView()
                    .musicDestinations(in: musicNavigationNamespace)
            }
        case .settings:
            NavigationStack(path: $settingsPath) {
                MeloXSettingsView()
                    .musicDestinations(in: musicNavigationNamespace)
            }
        }
    }

    private func popToRoot(_ tab: MeloXTab) {
        withAnimation(.snappy(duration: 0.2)) {
            switch tab {
            case .home: homePath = NavigationPath()
            case .explore: explorePath = NavigationPath()
            case .library: libraryPath = NavigationPath()
            case .search: searchPath = NavigationPath()
            case .settings: settingsPath = NavigationPath()
            }
        }
    }

    private var initialNowPlayingPage: NowPlayingPage {
        guard settings.rememberNowPlayingPage else { return .artwork }
        return NowPlayingPage(rawValue: settings.rememberedNowPlayingPage) ?? .artwork
    }

    private func openMusicRoute(_ route: MusicRoute) {
        guard playerPresentation == nil else {
            pendingMusicRoute = route
            playerPresentation = nil
            return
        }
        navigate(to: route)
    }

    private func openNeteaseShare(_ presentation: NeteaseSharePresentation) {
        presentNeteaseShare(presentation, fromNowPlaying: false)
    }

    private func presentNeteaseShare(
        _ presentation: NeteaseSharePresentation,
        fromNowPlaying: Bool
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            if fromNowPlaying {
                nowPlayingSharePresentation = presentation
            } else {
                neteaseSharePresentation = presentation
            }
        }
    }

    private func finishPendingSongNavigation() {
        guard let route = pendingMusicRoute else { return }
        pendingMusicRoute = nil
        navigate(to: route)
    }

    private func navigate(to route: MusicRoute) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .explore: explorePath.append(route)
        case .library: libraryPath.append(route)
        case .search: searchPath.append(route)
        case .settings: settingsPath.append(route)
        }
    }
}
