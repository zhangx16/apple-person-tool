# PersonalToolbox 直播重建记录

日期：2026-10-08。

用户要求完全覆盖旧项目。保留本地 Git 历史，删除原 Swift 工具箱、Modules、ShareExtension、
Xcode 工程、旧 IPA、旧发布流程和凭证辅助脚本；工作目录现在是 Flutter 直播工程。

上游来源：<https://github.com/liuchuancong/pure_live>，固定提交
`322c6547a2ea1b7c26e4f9090b8161f658d8906e`。根目录 LICENSE 保留上游 AGPL-3.0。
`docs/` 中其他上游历史文件只用于参考，不能作为定制版通过验收的证据。

## 修改范围

- 注册表仅启用 bilibili、douyu、huya、douyin、kuaishou、xiaohongshu、weibo、iptv。
- 推荐、搜索和平台配置共享该注册表；账号页去掉 YY、Bigo、Twitch、SOOP。
- 分享链接解析和网页搜索解析拒绝未保留平台。
- 发现页增加搜索与直播源快捷操作；圆角底栏、青绿主题、12px 栅格间距。
- 小屏和较大字号采用单列卡片；紧凑高度隐藏首页介绍，操作仍可从菜单进入。
- 自定义频道经标准 M3U 导入流程落库，处理重复名称确认并保留请求头。
- 默认关闭上游更新；更新检查和版本历史额外受编译开关保护，避免误安装上游二进制。
- 不自动连接上游 Firebase；移除云账号登录 UI，保留用户自己的 WebDAV/本地备份。
- iOS 标识沿用原项目；原 Swift 工程的旧 IPA 不适用于此 Flutter 工程。

## iPad 适配补充

用户明确要求适配 iPad。新增可滚动的自适应侧栏，在全尺寸 iPad 横屏展开文字导航，
竖屏和中等窗口显示图标侧栏，窄分屏沿用底部导航。主内容根据当前窗口尺寸重排。
视频页在 iPad 竖屏采用上下布局，横屏和矮窗口采用并排布局；IPTV 保留纯视频。
原生配置开启四向旋转、关闭强制全屏，主应用和扩展的部署目标统一为 15.6。
方向锁定判断使用物理显示尺寸，iPad 分屏时不会被误判为手机并锁定方向。

## 验证

已完成：

- Flutter 3.47.5 SDK 官方 SHA-256 核验通过；依赖解析成功。
- 54 项定向回归通过，新增的 iPad 旋转保留状态用例及相关 15 项 iPad 测试再次通过，合计 55 个不同用例。
- 测试覆盖自定义源的生产解析器、请求头往返、非法输入、站点裁剪、分享链接、语言包、播放器线路刷新。
- iPad 布局覆盖 507×768 分屏、744×1133、834×1194、1024×768、1194×834、1366×1024、720×360 窗口和双倍字号。
- 工作流 YAML、iOS plist、四向旋转与分屏配置检查通过；旧 Swift 工程和项目内 IPA 均已移除。
- 架构严格检查有 1 处上游已有跨域依赖：录像播放器依赖直播 GlobalPlayerService；原始参考工程运行同一检查也报同一处，本次没有新增架构违规。

最后一次 `flutter analyze --no-pub` 通过，无问题。
`flutter build bundle --debug --no-pub --target-platform linux-x64` 通过，
应用主体 Dart 编译和资源打包成功，输出在 `build/flutter_assets/`。
该目录是调试资源包，不是 APK、iOS .app 或 IPA，不能直接安装到 iPad。

未进行真机安装或平台直播实播验收。本机为 Linux，不具备 Xcode，因此没有生成或签名 iOS IPA；
新增的手动 iOS workflow 用于在 macOS 构建未签名 .app，尚未推送或触发。
