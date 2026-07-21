# Archive failed on `700349f`

Run: https://github.com/zhangx16/apple-person-tool/actions/runs/29810572779
Commit: `700349fd6e2148fe7f38104fe52d6e625478ae04`

## Grep errors
```
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ChatStreamKeepAlive.swift:113:21: error: reference to captured var 'self' in concurrently-executing code
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ChatStreamKeepAlive.swift:124:21: error: reference to captured var 'self' in concurrently-executing code
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    optional func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error)
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    optional func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error)
```

## Tail
```
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatListView.swift:25:23: warning: backward matching of the unlabeled trailing closure is deprecated; label the argument with 'action' to suppress this warning
                    ) {
~~~~~~~~~~~~~~~~~~~~~ ^
, action: 
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/AppleTheme.swift:458:8: note: 'init(symbol:title:message:pathHint:actionTitle:secondaryActionTitle:secondaryAction:tint:action:)' declared here
struct EmptyStateView: View {
       ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatListView.swift:35:23: warning: backward matching of the unlabeled trailing closure is deprecated; label the argument with 'action' to suppress this warning
                    ) {
~~~~~~~~~~~~~~~~~~~~~ ^
, action: 
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/AppleTheme.swift:458:8: note: 'init(symbol:title:message:pathHint:actionTitle:secondaryActionTitle:secondaryAction:tint:action:)' declared here
struct EmptyStateView: View {
       ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ImagineViewModel.swift:48:35: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    init(settings: AppSettings = .shared) {
                                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift:61:70: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    func attach(modelContext: ModelContext, settings: AppSettings = .shared) {
                                                                     ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift:831:19: warning: call to main actor-isolated instance method 'handleDidEnterBackground()' in a synchronous nonisolated context; this is an error in Swift 6
            self?.handleDidEnterBackground()
                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift:843:18: note: calls to instance method 'handleDidEnterBackground()' from outside of its actor context are implicitly asynchronous
    private func handleDidEnterBackground() {
                 ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift:838:19: warning: call to main actor-isolated instance method 'handleWillEnterForeground()' in a synchronous nonisolated context; this is an error in Swift 6
            self?.handleWillEnterForeground()
                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift:853:18: note: calls to instance method 'handleWillEnterForeground()' from outside of its actor context are implicitly asynchronous
    private func handleWillEnterForeground() {
                 ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ImagineViewModel.swift:55:70: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    func attach(modelContext: ModelContext, settings: AppSettings = .shared) {
                                                                     ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadViewModel.swift:55:35: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    init(settings: AppSettings = .shared) {
                                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ChatStreamKeepAlive.swift:113:46: warning: capture of 'note' with non-sendable type 'Notification' in a `@Sendable` closure
                    self?.handleInterruption(note)
                                             ^
Foundation.Notification:2:15: note: struct 'Notification' does not conform to the 'Sendable' protocol
public struct Notification : ReferenceConvertible, Equatable, Hashable {
              ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ChatStreamKeepAlive.swift:113:21: error: reference to captured var 'self' in concurrently-executing code
                    self?.handleInterruption(note)
                    ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ChatStreamKeepAlive.swift:124:21: error: reference to captured var 'self' in concurrently-executing code
                    self?.resumeIfNeeded()
                    ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/SettingsViewModel.swift:26:35: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    init(settings: AppSettings = .shared) {
                                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:1210:10: warning: main actor-isolated instance method 'webView(_:didFailProvisionalNavigation:withError:)' cannot be used to satisfy nonisolated protocol requirement
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
         ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:1210:10: note: add 'nonisolated' to 'webView(_:didFailProvisionalNavigation:withError:)' to make this instance method not isolated to the actor
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
         ^
    nonisolated 
WebKit.WKNavigationDelegate:26:19: note: 'webView(_:didFailProvisionalNavigation:withError:)' declared here
    optional func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error)
                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:1192:10: warning: main actor-isolated instance method 'webView(_:didFinish:)' cannot be used to satisfy nonisolated protocol requirement
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
         ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:1192:10: note: add 'nonisolated' to 'webView(_:didFinish:)' to make this instance method not isolated to the actor
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
         ^
    nonisolated 
WebKit.WKNavigationDelegate:32:19: note: 'webView(_:didFinish:)' declared here
    optional func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:1200:10: warning: main actor-isolated instance method 'webView(_:didFail:withError:)' cannot be used to satisfy nonisolated protocol requirement
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
         ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:1200:10: note: add 'nonisolated' to 'webView(_:didFail:withError:)' to make this instance method not isolated to the actor
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
         ^
    nonisolated 
WebKit.WKNavigationDelegate:36:19: note: 'webView(_:didFail:withError:)' declared here
    optional func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error)
                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:123:9: warning: expression is 'async' but is not marked with 'await'; this is an error in Swift 6
        req.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        await 
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:123:22: note: property access is 'async'
        req.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
                     ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift:406:21: warning: variable 'props' was never mutated; consider changing to 'let' constant
                var props: [HTTPCookiePropertyKey: Any] = [
                ~~~ ^
                let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/BilibiliDownloadService.swift:201:13: warning: variable 'bvid' was never mutated; consider changing to 'let' constant
        var bvid = Self.extractBVID(from: url)
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/BilibiliDownloadService.swift:202:13: warning: variable 'aid' was never mutated; consider changing to 'let' constant
        var aid = Self.extractAID(from: url).flatMap { Int($0) }
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AnniversaryDateUtils.swift:237:13: warning: variable 'yearsDiff' was never mutated; consider changing to 'let' constant
        var yearsDiff = targetYear - baseYear
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/CLSNews/CLSNewsHomeView.swift:236:16: warning: immutable value 'err' was never used; consider replacing with '_' or removing it
        if let err = result.errorMessage, result.fromCache {
           ~~~~^~~
           _
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

ProcessInfoPlistFile /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/InstallationBuildProductsLocation/Applications/PersonalToolbox.app/Info.plist /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Resources/Info.plist (in target 'PersonalToolbox' from project 'PersonalToolbox')
    cd /Users/runner/work/apple-person-tool/apple-person-tool
    builtin-infoPlistUtility /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Resources/Info.plist -producttype com.apple.product-type.application -genpkginfo /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/InstallationBuildProductsLocation/Applications/PersonalToolbox.app/PkgInfo -expandbuildsettings -format binary -platform iphoneos -additionalcontentfile /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/IntermediateBuildFilesPath/PersonalToolbox.build/Release-iphoneos/PersonalToolbox.build/assetcatalog_generated_info.plist -requiredArchitecture arm64 -o /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/InstallationBuildProductsLocation/Applications/PersonalToolbox.app/Info.plist

** ARCHIVE FAILED **


The following build commands failed:
	CompileSwift normal arm64 (in target 'PersonalToolbox' from project 'PersonalToolbox')
	SwiftCompile normal arm64 Compiling\ PersonalToolboxApp.swift,\ RootTabView.swift,\ AppSettings.swift,\ BiometricAuth.swift,\ Haptics.swift,\ LocalNotifier.swift,\ LiveHomeView.swift,\ ShareHandoff.swift,\ LocalJSONStore.swift,\ ActionRouter.swift,\ PasswordGenerator.swift,\ ClipboardStore.swift,\ ServiceHealthService.swift,\ RSSStore.swift,\ HabitTodoStore.swift,\ MarketQuotesService.swift,\ ExpressService.swift,\ ToolsHomeViews.swift,\ KeychainStore.swift,\ NetworkClient.swift,\ SSEParser.swift,\ ChatListView.swift,\ ChatThreadView.swift,\ ChatViewModel.swift,\ ImagineComposeView.swift,\ ImagineViewModel.swift,\ MediaBubbleView.swift,\ DownloadHomeView.swift,\ DownloadViewModel.swift,\ SystemVideoPlayer.swift,\ FilesListView.swift,\ TaskRowView.swift,\ KomariHomeView.swift,\ ChatStreamKeepAlive.swift,\ CheckinModels.swift,\ CheckinService.swift,\ CheckinHomeView.swift,\ KomariViewModel.swift,\ MonitorHomeView.swift,\ MonitorViewModel.swift,\ ServicesHubView.swift,\ ServiceProbeRow.swift,\ SettingsView.swift,\ SettingsViewModel.swift,\ SublinkHomeView.swift,\ SublinkViewModel.swift,\ AdminModels.swift,\ ChatModels.swift,\ ConversationEntity.swift,\ DownloadModels.swift,\ KomariModels.swift,\ SublinkModels.swift,\ ConversationStore.swift,\ ImagineService.swift,\ KomariService.swift,\ Sub2APIService.swift,\ Sub2AdminService.swift,\ SublinkService.swift,\ YTService.swift,\ DouyinService.swift,\ BilibiliDownloadService.swift,\ AppleTheme.swift,\ BrandComponents.swift,\ SelectableNavTitle.swift,\ ServiceBrandIcon.swift,\ MonitorShellView.swift,\ AnniversaryModels.swift,\ AnniversaryDateUtils.swift,\ AnniversaryStore.swift,\ AnniversaryHomeView.swift,\ AnniversaryEditors.swift,\ QRAssistantModels.swift,\ QRCodeToolkit.swift,\ QRAssistantStore.swift,\ QRAssistantHomeView.swift,\ QRScannerViews.swift,\ QRRedirectConfigView.swift,\ TranslatorModels.swift,\ TranslatorService.swift,\ TranslatorStore.swift,\ TranslatorHomeView.swift,\ TranslatorSettingsView.swift,\ CloudflareModels.swift,\ CloudflareService.swift,\ CloudflareHomeView.swift,\ CloudflareZoneDetailView.swift,\ CLSModels.swift,\ CLSNewsService.swift,\ CLSNewsHomeView.swift,\ IPCheckModels.swift,\ IPCheckService.swift,\ IPCheckHomeView.swift,\ LiveModels.swift,\ HuyaLiveService.swift,\ DouyuLiveService.swift,\ DouyinLiveService.swift,\ KuaishouLiveService.swift,\ LiveJSEngine.swift,\ LiveCryptoMD5.swift,\ LiveRoomView.swift,\ LiveVLCPlayerView.swift,\ LiveFollowStore.swift,\ LivePlayPrefs.swift,\ LiveRecentStore.swift,\ GeneratedAssetSymbols.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/App/PersonalToolboxApp.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/App/RootTabView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/BiometricAuth.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/Haptics.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/LocalNotifier.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ShareHandoff.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/LocalJSONStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ActionRouter.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/PasswordGenerator.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ClipboardStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ServiceHealthService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/RSSStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/HabitTodoStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/MarketQuotesService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ExpressService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Tools/ToolsHomeViews.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/KeychainStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/NetworkClient.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/SSEParser.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatListView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatThreadView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ChatViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ImagineComposeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/ImagineViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Chat/MediaBubbleView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/SystemVideoPlayer.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/FilesListView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/TaskRowView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Komari/KomariHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ChatStreamKeepAlive.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/CheckinModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CheckinService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Checkin/CheckinHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Komari/KomariViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Services/ServicesHubView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/ServiceProbeRow.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/SettingsView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/SettingsViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Sublink/SublinkHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Sublink/SublinkViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/AdminModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/ChatModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/ConversationEntity.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/DownloadModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/KomariModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/SublinkModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ConversationStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ImagineService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KomariService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/Sub2APIService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/Sub2AdminService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/SublinkService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/YTService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/BilibiliDownloadService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/AppleTheme.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/BrandComponents.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/SelectableNavTitle.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/ServiceBrandIcon.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorShellView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/AnniversaryModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AnniversaryDateUtils.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/AnniversaryStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Anniversary/AnniversaryHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Anniversary/AnniversaryEditors.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/QRAssistantModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/QRCodeToolkit.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/QRAssistantStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRAssistantHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRScannerViews.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRRedirectConfigView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/TranslatorModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/TranslatorService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/TranslatorStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Translator/TranslatorHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Translator/TranslatorSettingsView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/CloudflareModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CloudflareService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Cloudflare/CloudflareHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Cloudflare/CloudflareZoneDetailView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/CLSModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CLSNewsService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/CLSNews/CLSNewsHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/IPCheckModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/IPCheckService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/IPCheck/IPCheckHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/LiveModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/HuyaLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyuLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KuaishouLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveJSEngine.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveCryptoMD5.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveVLCPlayerView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveFollowStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LivePlayPrefs.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveRecentStore.swift /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/IntermediateBuildFilesPath/PersonalToolbox.build/Release-iphoneos/PersonalToolbox.build/DerivedSources/GeneratedAssetSymbols.swift (in target 'PersonalToolbox' from project 'PersonalToolbox')
(2 failures)
```
