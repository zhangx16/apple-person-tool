# 安装 PersonalToolbox IPA（Ad Hoc）

## 签名信息（与证书包对齐）

| 项 | 值 |
|----|-----|
| Team ID | `CTSQLK944L` |
| Bundle ID | `app.parsnip6345.lake8262` |
| 证书 | iPhone Distribution: Leroy Skinner |
| 描述文件 | `00008150-001A088E148B401C6F01CD` |
| 设备 UDID | `00008150-001A088E148B401C` |
| 分发方式 | **Ad Hoc**（仅登记设备） |

## 云端打包（GitHub Actions）

1. 打开仓库 **Settings → Secrets and variables → Actions**，添加：

   | Secret 名 | 内容 |
   |-----------|------|
   | `BUILD_CERTIFICATE_BASE64` | `cert.p12` 的 base64 |
   | `P12_PASSWORD` | p12 导出密码 |
   | `BUILD_PROVISION_PROFILE_BASE64` | `profile.mobileprovision` 的 base64 |
   | `KEYCHAIN_PASSWORD` | 任意随机字符串（仅 CI 临时钥匙串） |
   | `SHARE_BUILD_PROVISION_PROFILE_BASE64` | （可选）Share Extension 描述文件 base64 |
   | `SHARE_PROVISION_PROFILE_SPECIFIER` | （可选）Share Extension 描述文件名称 |

   Share Extension Bundle ID：`app.parsnip6345.lake8262.share`  
   App Group：`group.app.parsnip6345.lake8262`  
   未配置 Share 描述文件时，CI **自动去掉 Extension**，只打主 App IPA（主功能不受影响）。

2. **Actions → Build Ad Hoc IPA → Run workflow**（或 push 到 `main`）。
3. 构建成功后，在 run 页面 **Artifacts** 下载 `PersonalToolbox-ipa`。

## 装到 iPhone

1. iPhone：设置 → 隐私与安全性 → **开发者模式**（若提示）→ 打开并重启。
2. 用电脑安装（任选）：
   - **Windows**：3uTools / iMazing / Sideloadly（指向已签名 IPA）
   - **macOS**：Finder 选中设备 → 拖入 IPA，或 Apple Configurator
   - **AltStore / SideStore**：导入 IPA 安装
3. 首次打开：设置 → 通用 → VPN 与设备管理 → 信任 **Leroy Skinner** 证书。

## 注意

- Ad Hoc 包**只能**装在描述文件登记过的设备上；换手机需新描述文件并重新打包。
- 描述文件 / 证书过期后需更新 secrets 并重跑 Actions。
- **不要**把 p12 / 密码提交进 Git。
