# Archive failed on `a124928`

Run: https://github.com/zhangx16/apple-person-tool/actions/runs/29683806281
Commit: `a124928b8c95b0e35401019eaa32aad4e4b12f63`

## Grep errors
```
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Services/ServicesHubView.swift:7:42: error: cannot find 'LiveRecentStore' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Services/ServicesHubView.swift:220:32: error: cannot infer contextual base in reference to member 'live'
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    optional func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error)
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    optional func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error)
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/LiveModels.swift:160:31: error: cannot find 'LiveDetailCache' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/LiveModels.swift:170:15: error: cannot find 'LiveDetailCache' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:49:16: error: cannot find 'LivePlayPrefs' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:88:9: error: cannot find 'LivePlayPrefs' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:88:33: error: cannot infer contextual base in reference to member 'native'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:96:9: error: cannot find 'LivePlayPrefs' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:96:33: error: cannot infer contextual base in reference to member 'web'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:150:17: error: cannot find 'LivePlayPrefs' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:150:41: error: cannot infer contextual base in reference to member 'web'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:186:13: error: cannot find 'LivePlayPrefs' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:186:37: error: cannot infer contextual base in reference to member 'native'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:206:9: error: cannot find 'LivePlayPrefs' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:206:33: error: cannot infer contextual base in reference to member 'web'
```

## Tail
```
        var ordered: [(String, String)] = [
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ExpressService.swift:215:19: warning: value 'http' was defined but never used; consider replacing with boolean test
        guard let http = resp as? HTTPURLResponse else {
              ~~~~^~~~~~~     ~~~
                              is
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift:25:68: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    init(store: ConversationStore? = nil, settings: AppSettings = .shared) {
                                                                   ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ImagineViewModel.swift:48:35: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    init(settings: AppSettings = .shared) {
                                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift:31:70: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    func attach(modelContext: ModelContext, settings: AppSettings = .shared) {
                                                                     ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ImagineViewModel.swift:55:70: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    func attach(modelContext: ModelContext, settings: AppSettings = .shared) {
                                                                     ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadViewModel.swift:53:35: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    init(settings: AppSettings = .shared) {
                                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Services/ServicesHubView.swift:7:42: error: cannot find 'LiveRecentStore' in scope
    @ObservedObject private var recent = LiveRecentStore.shared
                                         ^~~~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Services/ServicesHubView.swift:220:32: error: cannot infer contextual base in reference to member 'live'
                recent.record(.live)
                              ~^~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/SettingsViewModel.swift:24:35: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    init(settings: AppSettings = .shared) {
                                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:947:10: warning: main actor-isolated instance method 'webView(_:didFailProvisionalNavigation:withError:)' cannot be used to satisfy nonisolated protocol requirement
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
         ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:947:10: note: add 'nonisolated' to 'webView(_:didFailProvisionalNavigation:withError:)' to make this instance method not isolated to the actor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
         ^
    nonisolated 
WebKit.WKNavigationDelegate:26:19: note: 'webView(_:didFailProvisionalNavigation:withError:)' declared here
    optional func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error)
                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:929:10: warning: main actor-isolated instance method 'webView(_:didFinish:)' cannot be used to satisfy nonisolated protocol requirement
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
         ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:929:10: note: add 'nonisolated' to 'webView(_:didFinish:)' to make this instance method not isolated to the actor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
         ^
    nonisolated 
WebKit.WKNavigationDelegate:32:19: note: 'webView(_:didFinish:)' declared here
    optional func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:937:10: warning: main actor-isolated instance method 'webView(_:didFail:withError:)' cannot be used to satisfy nonisolated protocol requirement
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
         ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:937:10: note: add 'nonisolated' to 'webView(_:didFail:withError:)' to make this instance method not isolated to the actor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
         ^
    nonisolated 
WebKit.WKNavigationDelegate:36:19: note: 'webView(_:didFail:withError:)' declared here
    optional func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error)
                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AnniversaryDateUtils.swift:237:13: warning: variable 'yearsDiff' was never mutated; consider changing to 'let' constant
        var yearsDiff = targetYear - baseYear
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/CLSNews/CLSNewsHomeView.swift:236:16: warning: immutable value 'err' was never used; consider replacing with '_' or removing it
        if let err = result.errorMessage, result.fromCache {
           ~~~~^~~
           _
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/LiveModels.swift:160:31: error: cannot find 'LiveDetailCache' in scope
        if let cached = await LiveDetailCache.shared.get(platform: platform, roomId: roomId) {
                              ^~~~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/LiveModels.swift:170:15: error: cannot find 'LiveDetailCache' in scope
        await LiveDetailCache.shared.set(detail)
              ^~~~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KuaishouLiveService.swift:357:13: warning: variable 'category' was never mutated; consider changing to 'let' constant
        var category = LiveJSON.string(gameInfo["name"])
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KuaishouLiveService.swift:435:13: warning: variable 'text' was never mutated; consider changing to 'let' constant
        var text = String(html[r]).replacingOccurrences(of: "undefined", with: "null")
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KuaishouLiveService.swift:483:13: warning: variable 'category' was never mutated; consider changing to 'let' constant
        var category = LiveJSON.string(gameInfo["name"])
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:49:16: error: cannot find 'LivePlayPrefs' in scope
        switch LivePlayPrefs.preferred(for: room.platform) {
               ^~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:88:9: error: cannot find 'LivePlayPrefs' in scope
        LivePlayPrefs.remember(.native, for: room.platform)
        ^~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:88:33: error: cannot infer contextual base in reference to member 'native'
        LivePlayPrefs.remember(.native, for: room.platform)
                               ~^~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:96:9: error: cannot find 'LivePlayPrefs' in scope
        LivePlayPrefs.remember(.web, for: room.platform)
        ^~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:96:33: error: cannot infer contextual base in reference to member 'web'
        LivePlayPrefs.remember(.web, for: room.platform)
                               ~^~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:150:17: error: cannot find 'LivePlayPrefs' in scope
                LivePlayPrefs.remember(.web, for: room.platform)
                ^~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:150:41: error: cannot infer contextual base in reference to member 'web'
                LivePlayPrefs.remember(.web, for: room.platform)
                                       ~^~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:186:13: error: cannot find 'LivePlayPrefs' in scope
            LivePlayPrefs.remember(.native, for: room.platform)
            ^~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:186:37: error: cannot infer contextual base in reference to member 'native'
            LivePlayPrefs.remember(.native, for: room.platform)
                                   ~^~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:206:9: error: cannot find 'LivePlayPrefs' in scope
        LivePlayPrefs.remember(.web, for: room.platform)
        ^~~~~~~~~~~~~
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift:206:33: error: cannot infer contextual base in reference to member 'web'
        LivePlayPrefs.remember(.web, for: room.platform)
                               ~^~~

ProcessInfoPlistFile /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/InstallationBuildProductsLocation/Applications/PersonalToolbox.app/Info.plist /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Resources/Info.plist (in target 'PersonalToolbox' from project 'PersonalToolbox')
    cd /Users/runner/work/apple-person-tool/apple-person-tool
    builtin-infoPlistUtility /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Resources/Info.plist -producttype com.apple.product-type.application -genpkginfo /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/InstallationBuildProductsLocation/Applications/PersonalToolbox.app/PkgInfo -expandbuildsettings -format binary -platform iphoneos -additionalcontentfile /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/IntermediateBuildFilesPath/PersonalToolbox.build/Release-iphoneos/PersonalToolbox.build/assetcatalog_generated_info.plist -requiredArchitecture arm64 -o /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/InstallationBuildProductsLocation/Applications/PersonalToolbox.app/Info.plist

** ARCHIVE FAILED **


The following build commands failed:
	CompileSwift normal arm64 (in target 'PersonalToolbox' from project 'PersonalToolbox')
	SwiftCompile normal arm64 Compiling\ PersonalToolboxApp.swift,\ RootTabView.swift,\ AppSettings.swift,\ BiometricAuth.swift,\ Haptics.swift,\ LocalNotifier.swift,\ LiveHomeView.swift,\ ShareHandoff.swift,\ LocalJSONStore.swift,\ ActionRouter.swift,\ PasswordGenerator.swift,\ ClipboardStore.swift,\ ServiceHealthService.swift,\ RSSStore.swift,\ HabitTodoStore.swift,\ MarketQuotesService.swift,\ ExpressService.swift,\ ToolsHomeViews.swift,\ KeychainStore.swift,\ NetworkClient.swift,\ SSEParser.swift,\ ChatListView.swift,\ ChatThreadView.swift,\ ChatViewModel.swift,\ ImagineComposeView.swift,\ ImagineViewModel.swift,\ MediaBubbleView.swift,\ DownloadHomeView.swift,\ DownloadViewModel.swift,\ SystemVideoPlayer.swift,\ FilesListView.swift,\ TaskRowView.swift,\ KomariHomeView.swift,\ KomariViewModel.swift,\ MonitorHomeView.swift,\ MonitorViewModel.swift,\ ServicesHubView.swift,\ ServiceProbeRow.swift,\ SettingsView.swift,\ SettingsViewModel.swift,\ SublinkHomeView.swift,\ SublinkViewModel.swift,\ AdminModels.swift,\ ChatModels.swift,\ ConversationEntity.swift,\ DownloadModels.swift,\ KomariModels.swift,\ SublinkModels.swift,\ ConversationStore.swift,\ ImagineService.swift,\ KomariService.swift,\ Sub2APIService.swift,\ Sub2AdminService.swift,\ SublinkService.swift,\ YTService.swift,\ DouyinService.swift,\ AppleTheme.swift,\ SelectableNavTitle.swift,\ ServiceBrandIcon.swift,\ MonitorShellView.swift,\ AnniversaryModels.swift,\ AnniversaryDateUtils.swift,\ AnniversaryStore.swift,\ AnniversaryHomeView.swift,\ AnniversaryEditors.swift,\ QRAssistantModels.swift,\ QRCodeToolkit.swift,\ QRAssistantStore.swift,\ QRAssistantHomeView.swift,\ QRScannerViews.swift,\ QRRedirectConfigView.swift,\ TranslatorModels.swift,\ TranslatorService.swift,\ TranslatorStore.swift,\ TranslatorHomeView.swift,\ TranslatorSettingsView.swift,\ CloudflareModels.swift,\ CloudflareService.swift,\ CloudflareHomeView.swift,\ CloudflareZoneDetailView.swift,\ CLSModels.swift,\ CLSNewsService.swift,\ CLSNewsHomeView.swift,\ IPCheckModels.swift,\ IPCheckService.swift,\ IPCheckHomeView.swift,\ LiveModels.swift,\ HuyaLiveService.swift,\ DouyuLiveService.swift,\ DouyinLiveService.swift,\ KuaishouLiveService.swift,\ LiveJSEngine.swift,\ LiveCryptoMD5.swift,\ LiveRoomView.swift,\ LiveVLCPlayerView.swift,\ LiveFollowStore.swift,\ GeneratedAssetSymbols.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/App/PersonalToolboxApp.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/App/RootTabView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/BiometricAuth.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/Haptics.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/LocalNotifier.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ShareHandoff.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/LocalJSONStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ActionRouter.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/PasswordGenerator.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ClipboardStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ServiceHealthService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/RSSStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/HabitTodoStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/MarketQuotesService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ExpressService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Tools/ToolsHomeViews.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/KeychainStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/NetworkClient.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/SSEParser.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatListView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatThreadView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ImagineComposeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ImagineViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/MediaBubbleView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/SystemVideoPlayer.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/FilesListView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/TaskRowView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Komari/KomariHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Komari/KomariViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Services/ServicesHubView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/ServiceProbeRow.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/SettingsView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/SettingsViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Sublink/SublinkHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Sublink/SublinkViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/AdminModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/ChatModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/ConversationEntity.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/DownloadModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/KomariModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/SublinkModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ConversationStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ImagineService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KomariService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/Sub2APIService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/Sub2AdminService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/SublinkService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/YTService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/AppleTheme.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/SelectableNavTitle.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/ServiceBrandIcon.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorShellView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/AnniversaryModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AnniversaryDateUtils.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/AnniversaryStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Anniversary/AnniversaryHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Anniversary/AnniversaryEditors.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/QRAssistantModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/QRCodeToolkit.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/QRAssistantStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRAssistantHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRScannerViews.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRRedirectConfigView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/TranslatorModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/TranslatorService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/TranslatorStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Translator/TranslatorHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Translator/TranslatorSettingsView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/CloudflareModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CloudflareService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Cloudflare/CloudflareHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Cloudflare/CloudflareZoneDetailView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/CLSModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CLSNewsService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/CLSNews/CLSNewsHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/IPCheckModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/IPCheckService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/IPCheck/IPCheckHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/LiveModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/HuyaLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyuLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KuaishouLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveJSEngine.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveCryptoMD5.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveVLCPlayerView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveFollowStore.swift /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/IntermediateBuildFilesPath/PersonalToolbox.build/Release-iphoneos/PersonalToolbox.build/DerivedSources/GeneratedAssetSymbols.swift (in target 'PersonalToolbox' from project 'PersonalToolbox')
(2 failures)
```
