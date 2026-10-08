# 随心直播 · Personal Live

PersonalToolbox 已完全重建为 Flutter 直播聚合播放器，原 Swift 工具箱工程及 IPA 已移除。

基于 [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live) 的
`322c6547a2ea1b7c26e4f9090b8161f658d8906e`，遵循 [AGPL-3.0](LICENSE)。
保留上游版权与许可证；代码中的 `pure_live` 包名沿用，应用展示名为「随心直播」。

## 保留的平台

哔哩哔哩、斗鱼、虎牙、抖音、快手、小红书、微博直播，以及 IPTV。
自定义直播源复用 IPTV 的数据库、解析器和播放器。
其他平台不会出现在平台列表、全平台搜索或账号设置中，其链接也不能进入直播播放流程。

小红书主要通过直播分享链接或房间标识进入，目前没有经过确认的公开推荐目录。
微博支持公共直播目录和房间查询。实际播放取决于开播状态、登录、地区限制及站点接口；
不把注册了适配器等同于已完成各站真机验收。

## 界面与功能

- 发现首页：主播搜索、分享链接打开、IPTV 和自定义源快捷入口。
- 青绿色 Material 3 主题，圆角底栏、统一平台图标、明暗主题。
- 直播卡片根据屏幕宽度和字体缩放调整列数；横屏紧凑界面保留菜单入口。
- 关注、分类、观看历史、弹幕、清晰度/线路切换、多画面及录像沿用上游实现。
- IPTV 支持本地/网络 M3U、TXT、节目单和订阅管理。
- 自定义源：频道名、直播 URL、可选 User-Agent/Referer，保存后在 IPTV 管理。
- 禁用上游自动更新和上游 Firebase 登录入口；本地备份、WebDAV 与局域网同步保留。

## iPad 适配

- iPhone / iPad 通用应用，iPad 支持四个方向，允许 Split View 与 Stage Manager 窗口调整。
- 宽窗口显示侧栏，1194px 等宽屏可展开文字导航；窄窗口切换底部导航。
- 侧栏可滚动，缩小窗口或开启大字体后仍可访问搜索、直播源、历史和设置。
- 竖屏视频在上、弹幕在下；横屏和较矮窗口并排显示，IPTV 保留纯视频布局。
- iPad 不强制锁定横竖屏，跟随系统和用户方向设置。
- 直播卡片根据当前内容区域与字号动态计算列数；直播源表单限宽并支持键盘避让。

工程部署目标设为 iOS / iPadOS 15.6。实际设备兼容性和原生播放器能力仍需 Xcode 构建及真机验证。

## 开发与验证

固定 Flutter **3.47.5** / Dart **3.13.4**，见 `.fvmrc`。

```bash
flutter pub get
flutter test --concurrency=2 test/personal_live
flutter analyze
```

播放器和 WebView 依赖通过锁文件及固定 Git commit 解析，首次解析需要网络。
Windows 工具入口为 `tool/flutterw.ps1`，Linux/macOS 可直接使用固定版本 Flutter。

## 构建

```bash
# Android，需要 Android SDK / JDK 17；没有 release 密钥时仅为测试签名。
flutter build apk --release --target-platform android-arm64

# iOS，需要 macOS / Xcode / CocoaPods；不生成可直接安装的签名 IPA。
flutter build ios --release --no-codesign
```

Android 应用 ID：`app.personaltoolbox.live`。
iOS 沿用原项目 Bundle ID `app.parsnip6345.lake8262` 和 Team `CTSQLK944L`。
分享扩展使用 `app.parsnip6345.lake8262.ShareExtension`，App Group 为
`group.app.parsnip6345.lake8262`；签名安装需为主应用和扩展配置匹配的描述文件。

`.github/workflows/check.yml` 提供手动质量检查；`build-ios.yml` 提供手动未签名 iOS 构建。
没有自动发布、推送、Telegram 发送或部署步骤。

本次验证结果见 [docs/PERSONAL_LIVE_REBUILD.md](docs/PERSONAL_LIVE_REBUILD.md)。
