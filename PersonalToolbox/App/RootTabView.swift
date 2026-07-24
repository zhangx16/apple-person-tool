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

    @State private var selectedTab: AppTab = .overview
    @State private var isUnlocked = false
    @State private var hideForSwitcher = false

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

                MusicRootView()
                    .tabItem { Label("音乐", systemImage: "music.note") }
                    .tag(AppTab.music)
                    .accessibilityLabel("音乐")

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
        .onAppear {
            applyInitialLockState()
            updateSwitcherRedaction(for: scenePhase)
            shareInbox.consumeOnLaunch()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: settings.requireBiometricUnlock) { _, enabled in
            if enabled {
                isUnlocked = true
            } else {
                isUnlocked = true
            }
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
    }

    private func updateSwitcherRedaction(for phase: ScenePhase) {
        guard settings.hideSensitiveInAppSwitcher else {
            hideForSwitcher = false
            return
        }
        hideForSwitcher = phase != .active
    }
}
