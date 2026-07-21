# StatusWidget

工程内已包含 **StatusWidget** target（`app.parsnip6345.lake8262.widget`）。

## 数据

主 App 总览刷新时调用 `AppGroupShared.publish`，写入：

- App Group：`group.app.parsnip6345.lake8262`
- 签到健康度、订阅到期摘要

## CI / Ad Hoc 签名

默认 CI **会剥离** App Group entitlements，并 **不嵌入** Widget（除非提供密钥）：

| Secret | 作用 |
|--------|------|
| `ENABLE_APP_GROUPS=1` | 保留 App Group entitlements |
| `WIDGET_BUILD_PROVISION_PROFILE_BASE64` | 安装 Widget 描述文件并嵌入 appex |
| `WIDGET_PROVISION_PROFILE_SPECIFIER` | Widget 的 profile 名称 |

请在 Apple Developer 为：

1. App ID `app.parsnip6345.lake8262` 启用 **App Groups**，组 ID 同上  
2. 新建 App ID `app.parsnip6345.lake8262.widget`，启用 App Groups  
3. 生成 Ad Hoc 描述文件并写入 GitHub Secrets  

本地 Xcode：Team 自动签名勾选 App Groups 即可调试小组件。
