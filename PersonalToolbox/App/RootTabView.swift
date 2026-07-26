import SwiftUI

enum AppTab: Hashable {
    case overview
    case live
    case music
    case services
    case settings
}

struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var shareInbox: ShareInbox
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var deepLink = AppDeepLinkStore.shared

    @State private var selectedTab: AppTab = .overview
    @State private var isUnlocked = false
    @State private var hideForSwitcher = false
    /// When true (default on Music tab), system tab bar is hidden so music section bar owns the bottom.
    @State private var musicHidesAppTabBar = true

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                OverviewHomeView(selectedTab: $selectedTab)
                    .tabItem { Label("总览", systemImage: "square.grid.2x2") }
                    .tag(AppTab.overview)
                    .accessibilityLabel("总览")

                LiveHomeView()
                    .tabItem { Label("直播", systemImage: "play.tv") }
                    .tag(AppTab.live)
                    .accessibilityLabel("直播")

                MusicRootView(appTabBarHidden: $musicHidesAppTabBar)
                    .tabItem { Label("音乐", systemImage: "music.note") }
                    .tag(AppTab.music)
                    .accessibilityLabel("音乐")
                    // Hide app tab bar while in Music so MeloX bottom bar can sit flush.
                    .toolbar(musicHidesAppTabBar ? .hidden : .visible, for: .tabBar)

                ServicesHubView(selectedTab: $selectedTab)
                    .tabItem { Label("服务", systemImage: "shippingbox") }
                    .tag(AppTab.services)
                    .accessibilityLabel("服务")

                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(AppTab.settings)
                    .accessibilityLabel("设置")
            }
            .tint(Color.accentColor)
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
            .onChange(of: selectedTab) { _, tab in
                // Entering Music: reclaim bottom; leaving: always restore app tabs.
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
                .presentationDetents([.medium, .large])
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
        }
        .onAppear {
            applyInitialLockState()
            updateSwitcherRedaction(for: scenePhase)
            shareInbox.consumeOnLaunch()
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
            ExpressHomeView(prefill: tracking)
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
