import SwiftUI

enum AppTab: Hashable {
    case chat
    case monitor
    case services
    case download
    case settings
}

struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .chat
    @State private var isUnlocked = false
    @State private var hideForSwitcher = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ChatListView(selectedTab: $selectedTab)
                    .tabItem { Label("助手", systemImage: "sparkles") }
                    .tag(AppTab.chat)
                    .accessibilityLabel("助手")

                MonitorHomeView()
                    .tabItem { Label("监控", systemImage: "chart.bar.fill") }
                    .tag(AppTab.monitor)
                    .accessibilityLabel("Sub2API 监控")

                ServicesHubView(selectedTab: $selectedTab)
                    .tabItem { Label("服务", systemImage: "square.grid.2x2.fill") }
                    .tag(AppTab.services)
                    .accessibilityLabel("服务")

                DownloadHomeView(isTabSelected: selectedTab == .download)
                    .tabItem { Label("下载", systemImage: "arrow.down.circle") }
                    .tag(AppTab.download)
                    .accessibilityLabel("下载")

                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(AppTab.settings)
                    .accessibilityLabel("设置")
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
        .onAppear {
            applyInitialLockState()
            updateSwitcherRedaction(for: scenePhase)
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
