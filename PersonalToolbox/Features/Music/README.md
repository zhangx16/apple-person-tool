# 音乐模块（Kumone）

完整接入 [missuo/kumone](https://github.com/missuo/kumone) 的 iOS 客户端能力，
通过本地 Swift Package `Modules/Kumone` 与 PersonalToolbox 主工程隔离。

## 构建要求（已升级）

| 项 | 值 |
|----|-----|
| CI Runner | `macos-15` |
| Xcode | 优先 26.x → 16.x → 15.4 |
| 部署目标 | **iOS 18.0** |

Kumone 支持 iOS 16+；PersonalToolbox 保持自身 iOS 18 部署目标。CI 应优先选择 Xcode 26，
以覆盖 Kumone 最新的条件编译界面。

## 入口

`MusicRootView` → `KumoneCore.IOSMainWindow`

## 登录

Kumone 内置网易云二维码登录，Cookie 本地持久化并自动刷新。

## 能力

- 推荐、精选、私人漫游、聚合搜索和个人音乐库
- 歌单、专辑、歌手、每日推荐、红心与最近播放
- AVPlayer 队列、随机/单曲/列表循环与系统 Now Playing
- 沉浸播放页、同步歌词、翻译歌词和逐字歌词
- 原生灰色歌曲解锁与音质回退

## 许可

Kumone 使用 LGPL-3.0-only。其完整源码、LICENSE、COPYING 和修改历史保留在
`Modules/Kumone`；PersonalToolbox 通过独立 Swift Package 产品 `KumoneCore` 链接。
