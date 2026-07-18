# PersonalToolbox

个人 iOS 工具箱：接入本机 **sub2api**（Grok 对话 + Imagine）、**outlookEmailPlus**（邮件）、**yt-dlp-web-ui**（视频下载）。

设计文档见 [DESIGN.md](./DESIGN.md)。UI 对齐 [DESIGN_REFERENCE.md](./DESIGN_REFERENCE.md)（Apple Design）。

**打包安装到 iPhone（无 Mac）：** 见 [docs/INSTALL_IPA.md](./docs/INSTALL_IPA.md)。  
GitHub Actions 会在 `macos-14` 上用你的 **Ad Hoc** 证书打 IPA。

## 签名 / Bundle

| 项 | 值 |
|----|-----|
| Bundle ID | `app.parsnip6345.lake8262` |
| Team | `CTSQLK944L` |
| 分发 | Ad Hoc（描述文件已含你的 iPhone UDID） |

## 要求

- 云打包：GitHub Actions（仓库 Secrets 配置证书）
- 或本地：macOS + Xcode 15+（iOS 17 SDK）
- 本机服务可通过 HTTPS 域名访问（默认配置见设置页）

| 服务 | 默认域名 |
|------|----------|
| sub2api | `https://sub2api.996616.xyz` |
| 邮件 | `https://mail.996616.xyz` |
| yt-dlp | `https://yt.996616.xyz` |

## 打开工程（有 Mac 时）

```bash
open PersonalToolbox.xcodeproj
```

```bash
xcodebuild -project PersonalToolbox.xcodeproj -scheme PersonalToolbox \
  -destination 'generic/platform=iOS' -configuration Release archive
```

## 功能概览

1. **助手** — ChatGPT 风格流式对话（默认 `grok-4.3`）；「创作」入口支持 Grok Imagine 生图 / 编辑 / 视频  
2. **邮件** — 会话登录列账号，或 External API Key + 默认邮箱  
3. **下载** — 解析、清晰度、队列、完成文件分享  
4. **设置** — 三服务凭证、连通性探测、外观与隐私（Face ID 默认关）

## 仓库说明

- 集成产物在 `main`（`PLAN_ID=dbf5d164` 执行计划完成态）  
- 增量分支：`execute-plan/dbf5d164-pr-*`  
- PR-8（本地通知/弱网缓存）按产品决策首期跳过  

## 安全建议

个人服务暴露在公网时，建议配合 Tailscale / IP 白名单；API Key 与密码仅存 Keychain。
