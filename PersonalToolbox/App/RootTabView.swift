import SwiftUI

enum AppTab: Hashable {
    case chat
    case live
    case services
    case settings
}

struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var shareInbox: ShareInbox
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .chat
    @State private var isUnlocked = false
    @State private var hideForSwitcher = false

    var body: some View {
        ZStack {
            tabHost
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
        // Avoid animating the whole TabView tree (known source of tab-switch crashes).
        .animation(nil, value: selectedTab)
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

    /// iOS 18+ `Tab` API is more stable on recent OS builds; fall back for 17.
    @ViewBuilder
    private var tabHost: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("助手", systemImage: "sparkles", value: AppTab.chat) {
                    ChatListView(selectedTab: $selectedTab)
                }
                Tab("直播", systemImage: "tv", value: AppTab.live) {
                    LiveHomeView(isTabSelected: selectedTab == .live)
                }
                Tab("服务", systemImage: "square.grid.2x2.fill", value: AppTab.services) {
                    ServicesHubView(selectedTab: $selectedTab)
                }
                Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                ChatListView(selectedTab: $selectedTab)
                    .tabItem { Label("助手", systemImage: "sparkles") }
                    .tag(AppTab.chat)

                LiveHomeView(isTabSelected: selectedTab == .live)
                    .tabItem { Label("直播", systemImage: "tv") }
                    .tag(AppTab.live)

                ServicesHubView(selectedTab: $selectedTab)
                    .tabItem { Label("服务", systemImage: "square.grid.2x2.fill") }
                    .tag(AppTab.services)

                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(AppTab.settings)
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
