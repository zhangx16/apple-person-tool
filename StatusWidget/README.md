# StatusWidget（可选）

小组件源码已放在本目录。主 App 通过 App Group `group.app.parsnip6345.lake8262` 写入签到/订阅摘要。

**为何未默认并入 CI 主工程**：Widget Extension 需要独立 Bundle ID 与描述文件，Ad Hoc CI 的 profile 可能未包含扩展。

在 Xcode 中启用：
1. File → New → Target → Widget Extension
2. 使用本目录 `StatusWidget.swift` / entitlements
3. App Group 与主 App 一致：`group.app.parsnip6345.lake8262`
4. 描述文件勾选 App Group + Widget ID

主 App 在总览刷新时会 `AppGroupShared.publish(...)`。
