import SwiftUI

/// PersonalToolbox tab entry for MeloX (网易云音乐第三方客户端).
///
/// Assembles MeloX dependencies the same way `MeloXApp` does, then hosts
/// `MeloXContentView` under a single outer chrome title.
struct MusicRootView: View {
    @State private var settings: MeloXSettings
    @State private var api: NeteaseAPI
    @State private var library: LibraryStore
    @State private var cloud: CloudMusicStore
    @State private var downloads: DownloadStore
    @State private var player: PlayerStore
    @State private var screenAwakeCoordinator: ScreenAwakeCoordinator
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    init() {
        let settings = MeloXSettings()
        // Skip MeloX onboarding inside toolbox — jump straight into music UI.
        if !settings.hasCompletedOnboarding {
            settings.hasCompletedOnboarding = true
        }
        let api = NeteaseAPI(settings: settings)
        let library = LibraryStore(api: api, settings: settings)
        let cloud = CloudMusicStore(api: api, settings: settings)
        let downloads = DownloadStore(api: api, settings: settings)
        _settings = State(initialValue: settings)
        _api = State(initialValue: api)
        _library = State(initialValue: library)
        _cloud = State(initialValue: cloud)
        _downloads = State(initialValue: downloads)
        _player = State(
            initialValue: PlayerStore(
                api: api,
                settings: settings,
                downloads: downloads,
                onPlaybackRecorded: { song in
                    library.recordRecentlyPlayed(song)
                }
            )
        )
        _screenAwakeCoordinator = State(initialValue: ScreenAwakeCoordinator())
    }

    var body: some View {
        MeloXContentView(initialTab: settings.launchTab)
            .environment(settings)
            .environment(api)
            .environment(library)
            .environment(cloud)
            .environment(downloads)
            .environment(player)
            .environment(screenAwakeCoordinator)
            .environment(\.effectiveLyricsRefreshRate, effectiveLyricsRefreshRate)
            .tint(.red)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSProcessInfoPowerStateDidChange
                )
            ) { _ in
                isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }

    private var effectiveLyricsRefreshRate: LyricsRefreshRate {
        isLowPowerModeEnabled ? .lowPowerValue : settings.lyricsRefreshRate
    }
}
