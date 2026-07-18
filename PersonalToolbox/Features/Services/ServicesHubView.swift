import SwiftUI

/// Hub for self-hosted services + local tools (纪念日).
struct ServicesHubView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            List {
                Section("生活") {
                    NavigationLink {
                        AnniversaryHomeView()
                    } label: {
                        hubLabel(
                            title: "纪念日",
                            subtitle: "生日 · 倒计时 · 本地提醒",
                            brand: .anniversary
                        )
                    }
                    .accessibilityLabel("纪念日")

                    NavigationLink {
                        QRAssistantHomeView()
                    } label: {
                        hubLabel(
                            title: "二维码助手",
                            subtitle: "扫码 · 生成 · 智能跳转",
                            brand: .qrAssistant
                        )
                    }
                    .accessibilityLabel("二维码助手")

                    NavigationLink {
                        TranslatorHomeView()
                    } label: {
                        hubLabel(
                            title: "翻译器",
                            subtitle: "Sub2API · Google · 多引擎",
                            brand: .translator
                        )
                    }
                    .accessibilityLabel("翻译器")

                    NavigationLink {
                        CLSNewsHomeView()
                    } label: {
                        hubLabel(
                            title: "财联社电报",
                            subtitle: "实时电报 · 本地缓存",
                            brand: .clsNews
                        )
                    }
                    .accessibilityLabel("财联社电报")
                }

                Section("监控") {
                    Button {
                        selectedTab = .monitor
                    } label: {
                        hubLabel(
                            title: "Sub2 管理",
                            subtitle: "账号调度 · 用户余额 · 分组",
                            brand: .sub2
                        )
                    }
                    .accessibilityLabel("打开 Sub2API 管理")

                    NavigationLink {
                        KomariHomeView()
                    } label: {
                        hubLabel(
                            title: "Komari",
                            subtitle: settings.komariBaseURL,
                            brand: .komari
                        )
                    }
                    .accessibilityLabel("Komari 服务器监控")

                    NavigationLink {
                        CloudflareHomeView()
                    } label: {
                        hubLabel(
                            title: "Cloudflare",
                            subtitle: settings.isCloudflareConfigured
                                ? (settings.cloudflareAccountName.isEmpty
                                    ? "域名 · DNS · 用量"
                                    : settings.cloudflareAccountName)
                                : "未配置 API Token",
                            brand: .cloudflare
                        )
                    }
                    .accessibilityLabel("Cloudflare 管理")

                    NavigationLink {
                        IPCheckHomeView()
                    } label: {
                        hubLabel(
                            title: "IP 检测",
                            subtitle: "出口 IP · 分流/代理启发式",
                            brand: .ipCheck
                        )
                    }
                    .accessibilityLabel("IP 检测")
                }

                Section("订阅与节点") {
                    NavigationLink {
                        SublinkHomeView()
                    } label: {
                        hubLabel(
                            title: "SublinkX",
                            subtitle: settings.sublinkBaseURL,
                            brand: .sublink
                        )
                    }
                    .accessibilityLabel("SublinkX 订阅管理")
                }

                Section("媒体") {
                    Button {
                        selectedTab = .download
                    } label: {
                        hubLabel(
                            title: "视频下载",
                            subtitle: settings.ytBaseURL,
                            brand: .youtube
                        )
                    }
                    .accessibilityLabel("打开视频下载")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppleTheme.canvas)
            .navigationTitle("服务")
        }
    }

    private func hubLabel(title: String, subtitle: String, brand: ServiceBrand) -> some View {
        HStack(spacing: 14) {
            ServiceBrandIcon(brand: brand, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
