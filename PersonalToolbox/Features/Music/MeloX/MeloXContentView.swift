import SwiftUI
import UIKit

/// Native MeloX embedded in PersonalToolbox.
///
/// When the app tab bar is hidden, this module’s section bar sits at the
/// physical bottom. Swipe **up** on the bottom chrome to reveal the app tabs;
/// swipe **down** to hide them again and reclaim vertical space.
struct MeloXContentView: View {
    /// `true` = app TabView bar hidden; music section bar replaces it.
    @Binding var appTabBarHidden: Bool

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
    @ObservedObject private var deepLink = AppDeepLinkStore.shared

    init(initialTab: MeloXTab = .home, appTabBarHidden: Binding<Bool> = .constant(true)) {
        _selectedTab = State(initialValue: initialTab)
        _appTabBarHidden = appTabBarHidden
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
            .sheet(isPresented: Binding(
                get: { player.showsAppleMusicMatchPicker },
                set: { player.showsAppleMusicMatchPicker = $0 }
            )) {
                AppleMusicMatchPickerSheet()
            }
            .overlay(alignment: .top) {
                if let toast = player.toastMessage {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { player.dismissToast() }
                }
            }
            .animation(.snappy(duration: 0.28), value: player.toastMessage)
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
                Button("用 Apple Music 播放") {
                    player.dismissPlaybackIssue()
                    Task { await player.playViaAppleMusic(reason: .manual, recordRescue: false) }
                }
                Button("更换匹配…") {
                    player.dismissPlaybackIssue()
                    Task { await player.presentAppleMusicMatchPicker() }
                }
                Button("在 Apple Music 中搜索") {
                    let name = player.currentSong?.name ?? ""
                    let artist = player.currentSong?.artistText ?? ""
                    let q = [name, artist].filter { !$0.isEmpty }.joined(separator: " ")
                    player.dismissPlaybackIssue()
                    openAppleMusicSearch(q)
                }
                Button("好", role: .cancel) { player.dismissPlaybackIssue() }
            } message: {
                let chain = player.sourceStatusMessage.map { "\n\($0)" } ?? ""
                Text((player.playbackIssue?.message ?? "当前歌曲暂时无法播放。")
                    + chain
                    + "\n失败链：完整网易云 → Apple Music → 网易云试听兜底。需本机 Apple Music 会员。")
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
            .onAppear {
                if deepLink.pendingMusicURL != nil {
                    selectedTab = .search
                }
            }
            .onChange(of: deepLink.pendingMusicURL) { _, url in
                if url != nil {
                    selectedTab = .search
                }
            }
    }

    // MARK: - Bottom chrome

    private var bottomChrome: some View {
        VStack(spacing: 0) {
            if player.currentSong != nil {
                MiniPlayerView {
                    playerPresentation = .nowPlaying
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            musicSectionBar
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        // Swipe up → show app tabs; swipe down → hide app tabs (music bar stays).
        .gesture(tabBarRevealGesture)
        .animation(.snappy(duration: 0.28), value: player.currentSong?.id)
        .animation(.snappy(duration: 0.25), value: appTabBarHidden)
    }

    private var tabBarRevealGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let dy = value.translation.height
                let dx = value.translation.width
                guard abs(dy) > abs(dx), abs(dy) > 36 else { return }
                if dy < 0 {
                    // Up: reveal app tab bar
                    withAnimation(.snappy(duration: 0.25)) {
                        appTabBarHidden = false
                    }
                } else {
                    // Down: hide app tab bar again
                    withAnimation(.snappy(duration: 0.25)) {
                        appTabBarHidden = true
                    }
                }
            }
    }

    private var musicSectionBar: some View {
        VStack(spacing: 0) {
            // Hint when app tabs are hidden
            if appTabBarHidden {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .accessibilityLabel("上滑显示应用底部导航")
            }

            HStack(spacing: 0) {
                ForEach(MeloXTab.allCases) { tab in
                    let on = selectedTab == tab
                    Button {
                        if selectedTab == tab {
                            popToRoot(tab)
                        } else {
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 16, weight: on ? .semibold : .regular))
                                .symbolVariant(on ? .fill : .none)
                            Text(tab.title)
                                .font(.system(size: 9, weight: on ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(on ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, appTabBarHidden ? 8 : 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, appTabBarHidden ? 4 : 0)
        }
        .overlay(alignment: .top) { Divider() }
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

    /// Prefer native Apple Music app; fall back to web search.
    private func openAppleMusicSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let appURL = URL(string: "music://music.apple.com/search?term=\(encoded)"),
           UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
            return
        }
        if let web = URL(string: "https://music.apple.com/search?term=\(encoded)") {
            UIApplication.shared.open(web)
        }
    }
}
