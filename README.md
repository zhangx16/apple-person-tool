# ExpressTools · 快递聚合查询助手

一款本地优先的原生 iOS 快递助手。设计语言参考 PersonalToolbox，产品信息架构参考开源项目 [ExpressAssistant](https://github.com/Halo0sama/ExpressAssistant)，代码为独立 SwiftUI 实现。

## 功能

- 小米 / 京东 / 淘宝（菜鸟）/ 拼多多多账号绑定模型，凭证存 Keychain
- 在途首页，已完成与异常使用独立二级面板
- 运单号与承运商识别、快递100 官方实时查询
- 完整物流时间线、运输进度、预计到达、取件码识别
- 搜索、下拉批量刷新、快递日历
- 关注包裹，新物流动态发送本地通知
- AI 助手“云雀”、本机包裹上下文问答、预设问题与对话历史
- 多地址管理、可配置轮询、一次/每天/工作日/周末日报计划
- 数据仅存 App 沙盒，API 凭证仅存 Keychain
- iPhone / iPad、深色模式、Dynamic Type

## 构建

要求 Xcode 15+、iOS 17+。项目定义使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate
open ExpressTools.xcodeproj
```

首次运行后在“设置”中填写快递100 `customer` 与授权 `key`。Bundle ID 默认为 `com.zhangx16.expresstools`，签名前请设置自己的 Development Team。

## 数据源设计

工程按 ExpressAssistant 的多源模型重构，`DeliveryProvider` 把小米、京东、菜鸟、拼多多结果统一映射为 `ProviderParcel`。平台私有接口与登录态经常变化，账号凭证统一隔离在 Keychain；快递100是手动运单及轨迹查询的兜底 Provider。

## 隐私与许可

本项目无广告、无分析 SDK。运单号会在用户主动查询时发送给其配置的查询服务。项目采用 MIT License；与任何电商平台、快递公司或快递100均无隶属关系。
