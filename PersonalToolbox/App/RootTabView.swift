import SwiftUI

enum AppTab: Hashable {
    case overview
    case live
    case music
    case services
    case settings

    var title: String {
        switch self {
        case .overview: return "总览"
        case .live: return "直播"
        case .music: return "音乐"
        case .services: return "服务"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .live: return "play.tv"
        case .music: return "music.note"
        case .services: return "shippingbox"
        case .settings: return "gearshape"
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var shareInbox: ShareInbox
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var deepLink = AppDeepLinkStore.shared

    @State private var selectedTab: AppTab = .overview
    @State private var isUnlocked = false
    @State private var hideForSwitcher = false
    /// When true (default on Music tab), system tab bar is hidden so music section bar owns the bottom.
    /// Only applied on compact width (iPhone); iPad keeps the adaptable sidebar visible.
    @State private var musicHidesAppTabBar = true

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular || AdaptiveLayout.isPad
    }

    private var shouldHideTabBarForMusic: Bool {
        selectedTab == .music && musicHidesAppTabBar && !isRegularWidth
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                OverviewHomeView(selectedTab: $selectedTab)
                    .tabItem { Label(AppTab.overview.title, systemImage: AppTab.overview.systemImage) }
                    .tag(AppTab.overview)
                    .accessibilityLabel(AppTab.overview.title)

                LiveHomeView()
                    .tabItem { Label(AppTab.live.title, systemImage: AppTab.live.systemImage) }
                    .tag(AppTab.live)
                    .accessibilityLabel(AppTab.live.title)

                MusicRootView(appTabBarHidden: $musicHidesAppTabBar)
                    .tabItem { Label(AppTab.music.title, systemImage: AppTab.music.systemImage) }
                    .tag(AppTab.music)
                    .accessibilityLabel(AppTab.music.title)
                    // Hide app tab bar while in Music on iPhone so MeloX bottom bar can sit flush.
                    // On iPad (sidebarAdaptable) keep chrome so the sidebar remains available.
                    .toolbar(shouldHideTabBarForMusic ? .hidden : .visible, for: .tabBar)

                ServicesHubView(selectedTab: $selectedTab)
                    .tabItem { Label(AppTab.services.title, systemImage: AppTab.services.systemImage) }
                    .tag(AppTab.services)
                    .accessibilityLabel(AppTab.services.title)

                SettingsView()
                    .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                    .tag(AppTab.settings)
                    .accessibilityLabel(AppTab.settings.title)
            }
            // iOS 18+: bottom tabs on iPhone; sidebar (collapsible) on iPad / regular width.
            .tabViewStyle(.sidebarAdaptable)
            .tint(Color.accentColor)
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
            .onChange(of: selectedTab) { _, tab in
                // Entering Music: reclaim bottom on phone; leaving: always restore app tabs.
                if tab == .music {
                    musicHidesAppTabBar = true
                } else {
                    musicHidesAppTabBar = false
                }
            }
            .preferredColorScheme(preferredScheme)
            .allowsHitTesting(isContentInteractive)
            .accessibilityHidden(!isContentInteractive)

            if hideForSwitcher {
                PrivacyCoverView()
                    .transition(.opacity)
            }

            if settings.requireBiometricUnlock && !isUnlocked {
                BiometricLockView {
                    isUnlocked = true
                }
                .transition(.opacity)
                .zIndex(1)
            }

            // Global clipboard smart bar (top). Hidden under lock / switcher cover.
            if isContentInteractive, !hideForSwitcher {
                ClipboardSmartBar(selectedTab: $selectedTab)
                    .environmentObject(settings)
                    .zIndex(2)
            }
        }
        .animation(AppleTheme.preferredSnappy, value: hideForSwitcher)
        .animation(AppleTheme.preferredSnappy, value: isUnlocked)
        .sheet(isPresented: $shareInbox.showSheet) {
            if let payload = shareInbox.pendingPayload {
                NavigationStack {
                    QuickActionsHomeView()
                        .navigationTitle("分享传入")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { shareInbox.showSheet = false }
                            }
                        }
                        .onAppear {
                            if !payload.combinedText.isEmpty {
                                ClipboardStore.shared.copyToPasteboard(payload.combinedText)
                            }
                        }
                }
                .environmentObject(settings)
                .presentationDetents(isRegularWidth ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $deepLink.presentSheet) { sheet in
            NavigationStack {
                deepLinkSheetContent(sheet)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { deepLink.presentSheet = nil }
                        }
                    }
            }
            .environmentObject(settings)
            .presentationDetents(isRegularWidth ? [.large] : [.medium, .large])
        }
        .onAppear {
            applyInitialLockState()
            updateSwitcherRedaction(for: scenePhase)
            shareInbox.consumeOnLaunch()
            OrientationHelper.restoreDefault()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: settings.requireBiometricUnlock) { _, enabled in
            // Enabling the lock must take effect immediately; disabling always unlocks.
            isUnlocked = !enabled
        }
        .onChange(of: deepLink.requestedTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            deepLink.requestedTab = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: ForegroundNotificationDelegate.routeNotification)) { note in
            if let info = note.userInfo {
                deepLink.handleUserInfo(info)
            }
        }
    }

    @ViewBuilder
    private func deepLinkSheetContent(_ sheet: AppDeepLinkStore.DeepLinkSheet) -> some View {
        switch sheet {
        case .ipCheck(let ip):
            IPCheckHomeView(initialIP: ip)
        case .download(let url):
            DownloadHomeView(isTabSelected: true, initialURL: url.isEmpty ? nil : url)
                .navigationTitle("视频下载")
        case .express(let tracking):
            ExpressAssistantRootView(prefill: tracking)
        case .watchLater:
            WatchLaterHomeView()
        case .proxyPack:
            ProxyNodePackView()
        case .controlCenter:
            ControlCenterView()
        case .subscriptions:
            SubscriptionHomeView()
        }
    }

    private var preferredScheme: ColorScheme? {
        switch AppSettings.Appearance(rawValue: settings.appearance) {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }

    private var isContentInteractive: Bool {
        !(settings.requireBiometricUnlock && !isUnlocked)
    }

    private func applyInitialLockState() {
        isUnlocked = !settings.requireBiometricUnlock
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        updateSwitcherRedaction(for: phase)
        if settings.requireBiometricUnlock {
            switch phase {
            case .background, .inactive:
                isUnlocked = false
            default:
                break
            }
        }
        if phase == .active {
            LiveOpenNotifyService.evaluate(settings: settings)
            // Re-assert chrome orientation after returning from background (e.g. after video).
            if OrientationHelper.mask == .landscape {
                // Still in a fullscreen player path — leave alone.
            } else {
                OrientationHelper.restoreDefault()
            }
        }
    }

    private func updateSwitcherRedaction(for phase: ScenePhase) {
        guard settings.hideSensitiveInAppSwitcher else {
            hideForSwitcher = false
            return
        }
        hideForSwitcher = phase != .active
    }
}
