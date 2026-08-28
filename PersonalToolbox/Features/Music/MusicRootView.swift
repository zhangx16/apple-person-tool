import SwiftUI
import KumoneCore

/// Kumone music module entry embedded in PersonalToolbox.
struct MusicRootView: View {
    @Binding var appTabBarHidden: Bool

    init(appTabBarHidden: Binding<Bool> = .constant(true)) {
        _appTabBarHidden = appTabBarHidden
    }

    var body: some View {
        IOSMainWindow()
        .onAppear {
            appTabBarHidden = true
        }
        .onDisappear {
            appTabBarHidden = false
        }
    }
}
