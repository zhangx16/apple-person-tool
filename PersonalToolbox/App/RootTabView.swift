import SwiftUI

enum AppTab: Hashable {
    case chat
    case mail
    case download
    case settings
}

struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .chat
    /// When `requireBiometricUnlock` is on, content stays locked until auth succeeds.
    @State private var isUnlocked = false
    /// App-switcher redaction when `hideSensitiveInAppSwitcher` is on.
    @State private var hideForSwitcher = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ChatListView(selectedTab: $selectedTab)
                    .tabItem {
                        Label("助手", systemImage: "sparkles")
                    }
                    .tag(AppTab.chat)
                    .accessibilityLabel("助手")

                AccountListView()
                    .tabItem {
                        Label("邮件", systemImage: "envelope")
                    }
                    .tag(AppTab.mail)
                    .accessibilityLabel("邮件")

                DownloadHomeView(isTabSelected: selectedTab == .download)
                    .tabItem {
                        Label("下载", systemImage: "arrow.down.circle")
                    }
                    .tag(AppTab.download)
                    .accessibilityLabel("下载")

                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape")
                    }
                    .tag(AppTab.settings)
                    .accessibilityLabel("设置")
            }
            .preferredColorScheme(preferredScheme)
            // Dim interactive content while locked (still under lock overlay).
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
                // Settings only commits `true` after a successful preflight auth.
                // Stay unlocked for this session; re-lock on next background.
                isUnlocked = true
            } else {
                isUnlocked = true
            }
        }
        .onChange(of: settings.hideSensitiveInAppSwitcher) { _, enabled in
            if !enabled {
                hideForSwitcher = false
            } else {
                updateSwitcherRedaction(for: scenePhase)
            }
        }
    }

    private var isContentInteractive: Bool {
        if settings.requireBiometricUnlock && !isUnlocked { return false }
        if hideForSwitcher { return false }
        return true
    }

    private var preferredScheme: ColorScheme? {
        switch AppSettings.Appearance(rawValue: settings.appearance) {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }

    private func applyInitialLockState() {
        if settings.requireBiometricUnlock {
            isUnlocked = false
        } else {
            isUnlocked = true
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        updateSwitcherRedaction(for: phase)
        // Re-lock when leaving the app so a stolen unlocked phone stays protected.
        if phase == .background, settings.requireBiometricUnlock {
            isUnlocked = false
        }
    }

    private func updateSwitcherRedaction(for phase: ScenePhase) {
        guard settings.hideSensitiveInAppSwitcher else {
            hideForSwitcher = false
            return
        }
        // Cover on inactive (app switcher / control center) and background.
        hideForSwitcher = phase != .active
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppSettings.shared)
}
