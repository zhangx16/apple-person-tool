# Archive failed on `5b71e86`

Run: https://github.com/zhangx16/apple-person-tool/actions/runs/29837964638
Commit: `5b71e8677ac631c374495d10f5d1aa307b337942`

## Grep errors
```
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/App/AppIntentsSupport.swift:72:9: error: cannot convert value of type '[AppShortcut]' to expected argument type 'AppShortcut'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:123:61: error: type 'String' does not conform to protocol 'Error'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:138:51: error: type 'String' does not conform to protocol 'Error'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:134:34: error: type 'String' does not conform to protocol 'Error'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:201:39: error: type 'String' does not conform to protocol 'Error'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:150:25: error: cannot infer contextual base in reference to member 'failure'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:164:34: error: cannot infer contextual base in reference to member 'failure'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:196:21: error: cannot infer contextual base in reference to member 'success'
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:212:17: error: cannot find 'kSecOIDX509V1ValidityNotAfter' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:213:17: error: cannot find 'kSecOIDX509V1IssuerName' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:215:32: error: cannot find 'SecCertificateCopyValues' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:219:41: error: cannot find 'kSecOIDX509V1ValidityNotAfter' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:220:38: error: cannot find 'kSecPropertyKeyValue' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:232:39: error: cannot find 'kSecOIDX509V1IssuerName' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:233:36: error: cannot find 'kSecPropertyKeyValue' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:235:44: error: cannot find 'kSecPropertyKeyLabel' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift:236:44: error: cannot find 'kSecPropertyKeyValue' in scope
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:802:40: error: main actor-isolated property 'sub2apiBaseURL' can not be referenced from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:803:35: error: main actor-isolated property 'ytBaseURL' can not be referenced from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:804:40: error: main actor-isolated property 'sublinkBaseURL' can not be referenced from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:805:39: error: main actor-isolated property 'komariBaseURL' can not be referenced from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:806:40: error: main actor-isolated property 'checkinBaseURL' can not be referenced from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:807:36: error: main actor-isolated property 'clsFeedURL' can not be referenced from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:808:41: error: main actor-isolated property 'fastNoteBaseURL' can not be referenced from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:809:41: error: main actor-isolated property 'nextTerminalURL' can not be referenced from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:824:64: error: main actor-isolated property 'sub2apiBaseURL' can not be mutated from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:825:59: error: main actor-isolated property 'ytBaseURL' can not be mutated from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:826:64: error: main actor-isolated property 'sublinkBaseURL' can not be mutated from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:827:63: error: main actor-isolated property 'komariBaseURL' can not be mutated from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:828:64: error: main actor-isolated property 'checkinBaseURL' can not be mutated from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:829:60: error: main actor-isolated property 'clsFeedURL' can not be mutated from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:830:65: error: main actor-isolated property 'fastNoteBaseURL' can not be mutated from a non-isolated context
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:831:65: error: main actor-isolated property 'nextTerminalURL' can not be mutated from a non-isolated context
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    optional func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error)
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    optional func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error)
```

## Tail
```
    @Published var komariBaseURL: String {
                   ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:819:17: note: add '@MainActor' to make static method 'importSafeFields(json:settings:)' part of global actor 'MainActor'
    static func importSafeFields(json: String, settings: AppSettings) -> String {
                ^
    @MainActor 
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:828:64: error: main actor-isolated property 'checkinBaseURL' can not be mutated from a non-isolated context
        if let v = obj["checkinBaseURL"] as? String { settings.checkinBaseURL = v }
                                                               ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:70:20: note: mutation of this property is only permitted within the actor
    @Published var checkinBaseURL: String {
                   ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:819:17: note: add '@MainActor' to make static method 'importSafeFields(json:settings:)' part of global actor 'MainActor'
    static func importSafeFields(json: String, settings: AppSettings) -> String {
                ^
    @MainActor 
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:829:60: error: main actor-isolated property 'clsFeedURL' can not be mutated from a non-isolated context
        if let v = obj["clsFeedURL"] as? String { settings.clsFeedURL = v }
                                                           ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:118:20: note: mutation of this property is only permitted within the actor
    @Published var clsFeedURL: String {
                   ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:819:17: note: add '@MainActor' to make static method 'importSafeFields(json:settings:)' part of global actor 'MainActor'
    static func importSafeFields(json: String, settings: AppSettings) -> String {
                ^
    @MainActor 
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:830:65: error: main actor-isolated property 'fastNoteBaseURL' can not be mutated from a non-isolated context
        if let v = obj["fastNoteBaseURL"] as? String { settings.fastNoteBaseURL = v }
                                                                ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:80:20: note: mutation of this property is only permitted within the actor
    @Published var fastNoteBaseURL: String {
                   ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:819:17: note: add '@MainActor' to make static method 'importSafeFields(json:settings:)' part of global actor 'MainActor'
    static func importSafeFields(json: String, settings: AppSettings) -> String {
                ^
    @MainActor 
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:831:65: error: main actor-isolated property 'nextTerminalURL' can not be mutated from a non-isolated context
        if let v = obj["nextTerminalURL"] as? String { settings.nextTerminalURL = v }
                                                                ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:94:20: note: mutation of this property is only permitted within the actor
    @Published var nextTerminalURL: String {
                   ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift:819:17: note: add '@MainActor' to make static method 'importSafeFields(json:settings:)' part of global actor 'MainActor'
    static func importSafeFields(json: String, settings: AppSettings) -> String {
                ^
    @MainActor 
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/OrientationHelper.swift:40:26: warning: 'attemptRotationToDeviceOrientation()' was deprecated in iOS 16.0: Please use instance method `setNeedsUpdateOfSupportedInterfaceOrientations`.
        UIViewController.attemptRotationToDeviceOrientation()
                         ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ExpressService.swift:192:13: warning: variable 'ordered' was never mutated; consider changing to 'let' constant
        var ordered: [(String, String)] = [
        ~~~ ^
        let
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ExpressService.swift:215:19: warning: value 'http' was defined but never used; consider replacing with boolean test
        guard let http = resp as? HTTPURLResponse else {
              ~~~~^~~~~~~     ~~~
                              is
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadViewModel.swift:55:35: warning: main actor-isolated static property 'shared' can not be referenced from a non-isolated context; this is an error in Swift 6
    init(settings: AppSettings = .shared) {
                                  ^
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift:6:16: note: static property declared here
    static let shared = AppSettings()
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
	SwiftCompile normal arm64 Compiling\ PersonalToolboxApp.swift,\ RootTabView.swift,\ OverviewHomeView.swift,\ AppGroupShared.swift,\ AppIntentsSupport.swift,\ ActivityEventStore.swift,\ SubscriptionStore.swift,\ ReminderStore.swift,\ CertExpiryService.swift,\ FastNoteSyncService.swift,\ SSHHostStore.swift,\ LifeExtrasViews.swift,\ AppSettings.swift,\ BiometricAuth.swift,\ Haptics.swift,\ OrientationHelper.swift,\ LocalNotifier.swift,\ LiveHomeView.swift,\ ShareHandoff.swift,\ LocalJSONStore.swift,\ ActionRouter.swift,\ PasswordGenerator.swift,\ ClipboardStore.swift,\ ServiceHealthService.swift,\ RSSStore.swift,\ HabitTodoStore.swift,\ MarketQuotesService.swift,\ ExpressService.swift,\ ToolsHomeViews.swift,\ KeychainStore.swift,\ NetworkClient.swift,\ SSEParser.swift,\ DownloadHomeView.swift,\ DownloadViewModel.swift,\ SystemVideoPlayer.swift,\ FilesListView.swift,\ TaskRowView.swift,\ KomariHomeView.swift,\ CheckinModels.swift,\ CheckinService.swift,\ CheckinHomeView.swift,\ KomariViewModel.swift,\ MonitorHomeView.swift,\ MonitorViewModel.swift,\ ServicesHubView.swift,\ ServiceProbeRow.swift,\ SettingsView.swift,\ SettingsViewModel.swift,\ SublinkHomeView.swift,\ SublinkViewModel.swift,\ AdminModels.swift,\ ChatModels.swift,\ DownloadModels.swift,\ KomariModels.swift,\ SublinkModels.swift,\ KomariService.swift,\ Sub2APIService.swift,\ Sub2AdminService.swift,\ SublinkService.swift,\ YTService.swift,\ DouyinService.swift,\ BilibiliDownloadService.swift,\ AppleTheme.swift,\ BrandComponents.swift,\ SelectableNavTitle.swift,\ ServiceBrandIcon.swift,\ MonitorShellView.swift,\ AnniversaryModels.swift,\ AnniversaryDateUtils.swift,\ AnniversaryStore.swift,\ AnniversaryHomeView.swift,\ AnniversaryEditors.swift,\ QRAssistantModels.swift,\ QRCodeToolkit.swift,\ QRAssistantStore.swift,\ QRAssistantHomeView.swift,\ QRScannerViews.swift,\ QRRedirectConfigView.swift,\ TranslatorModels.swift,\ TranslatorService.swift,\ TranslatorStore.swift,\ TranslatorHomeView.swift,\ TranslatorSettingsView.swift,\ CloudflareModels.swift,\ CloudflareService.swift,\ CloudflareHomeView.swift,\ CloudflareZoneDetailView.swift,\ CLSModels.swift,\ CLSNewsService.swift,\ CLSNewsHomeView.swift,\ IPCheckModels.swift,\ IPCheckService.swift,\ IPCheckHomeView.swift,\ LiveModels.swift,\ HuyaLiveService.swift,\ DouyuLiveService.swift,\ DouyinLiveService.swift,\ KuaishouLiveService.swift,\ LiveJSEngine.swift,\ LiveCryptoMD5.swift,\ LiveRoomView.swift,\ LiveVLCPlayerView.swift,\ LiveFollowStore.swift,\ LivePlayPrefs.swift,\ LiveRecentStore.swift,\ GeneratedAssetSymbols.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/App/PersonalToolboxApp.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/App/RootTabView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Overview/OverviewHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppGroupShared.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/App/AppIntentsSupport.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ActivityEventStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/SubscriptionStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ReminderStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CertExpiryService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/FastNoteSyncService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/SSHHostStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Life/LifeExtrasViews.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AppSettings.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/BiometricAuth.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/Haptics.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/OrientationHelper.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/LocalNotifier.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ShareHandoff.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/LocalJSONStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/ActionRouter.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/PasswordGenerator.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ClipboardStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ServiceHealthService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/RSSStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/HabitTodoStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/MarketQuotesService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/ExpressService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Tools/ToolsHomeViews.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/KeychainStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/NetworkClient.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/SSEParser.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/DownloadViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/SystemVideoPlayer.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/FilesListView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Download/TaskRowView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Komari/KomariHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/CheckinModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CheckinService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Checkin/CheckinHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Komari/KomariViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Services/ServicesHubView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/ServiceProbeRow.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/SettingsView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Settings/SettingsViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Sublink/SublinkHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Sublink/SublinkViewModel.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/AdminModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/ChatModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/DownloadModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/KomariModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/SublinkModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KomariService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/Sub2APIService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/Sub2AdminService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/SublinkService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/YTService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/BilibiliDownloadService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/AppleTheme.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/BrandComponents.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/SelectableNavTitle.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Theme/ServiceBrandIcon.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Monitor/MonitorShellView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/AnniversaryModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/AnniversaryDateUtils.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/AnniversaryStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Anniversary/AnniversaryHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Anniversary/AnniversaryEditors.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/QRAssistantModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Core/QRCodeToolkit.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/QRAssistantStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRAssistantHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRScannerViews.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/QRAssistant/QRRedirectConfigView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/TranslatorModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/TranslatorService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/TranslatorStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Translator/TranslatorHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Translator/TranslatorSettingsView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/CloudflareModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CloudflareService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Cloudflare/CloudflareHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Cloudflare/CloudflareZoneDetailView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/CLSModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/CLSNewsService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/CLSNews/CLSNewsHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/IPCheckModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/IPCheckService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/IPCheck/IPCheckHomeView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Models/LiveModels.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/HuyaLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyuLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/DouyinLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/KuaishouLiveService.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveJSEngine.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveCryptoMD5.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveRoomView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Features/Live/LiveVLCPlayerView.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveFollowStore.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LivePlayPrefs.swift /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Services/LiveRecentStore.swift /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/IntermediateBuildFilesPath/PersonalToolbox.build/Release-iphoneos/PersonalToolbox.build/DerivedSources/GeneratedAssetSymbols.swift (in target 'PersonalToolbox' from project 'PersonalToolbox')
(2 failures)
```
