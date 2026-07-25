# 音乐模块（原生 MeloX）

基于 [youshen2/MeloX](https://github.com/youshen2/MeloX) 的网易云音乐原生客户端。

## 构建要求（已升级）

| 项 | 值 |
|----|-----|
| CI Runner | `macos-15` |
| Xcode | 优先 26.x → 16.x → 15.4 |
| 部署目标 | **iOS 18.0**（启用 TextProxy / textRenderer / 全屏歌词等 API） |

此前未直接升版本，是因为仓库 CI 长期锁在 Xcode 15.4 + iOS 17，全量 MeloX（iOS 26 API）无法过编；现已按你的要求升级。

## 入口

`MusicRootView` → `MeloXContentView`（顶部分段，避免双底栏）

## 登录

设置 → 登录网易云（WKWebView 抓 Cookie，兼容面更广）
