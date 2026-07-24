# 音乐模块（MeloX）

基于开源项目 [youshen2/MeloX](https://github.com/youshen2/MeloX) 接入的网易云音乐客户端。

## 说明

- 源码位于 `Features/Music/MeloX/`，入口为 `MusicRootView`。
- 类型冲突已重命名：`MeloXSettings` / `MeloXTab` / `MeloXSettingsView` / `MeloXContentView`。
- 上游目标为 iOS 26；本仓库做了 iOS 17 兼容（见 `MeloXCompatibility.swift`），并去掉嵌套底栏，改为顶部分段。
- 依赖 SPM：`GRDB.swift`（下载库本地库）。
- 登录：模块内「设置」→ 网易云网页登录；Cookie 仅存本机。

## 许可

MeloX 使用其仓库 LICENSE；与网易云音乐官方无隶属关系。
