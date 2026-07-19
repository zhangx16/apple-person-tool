import SwiftUI

/// Hub for self-hosted services + local tools — card sections, soft hierarchy.
struct ServicesHubView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("效率", symbol: "bolt.fill") {
                        hubLink("快捷动作中心", "剪贴板 / 链接 / 单号智能分流", .quickActions) {
                            QuickActionsHomeView()
                        }
                        hubLink("剪贴板工具箱", "历史 · 验证码 · 动作推荐", .clipboard) {
                            ClipboardHomeView()
                        }
                        hubLink("密码生成器", "本地随机 · 强度提示", .password) {
                            PasswordGeneratorHomeView()
                        }
                    }

                    section("生活", symbol: "heart.fill") {
                        hubLink("纪念日", "生日 · 倒计时 · 本地提醒", .anniversary) {
                            AnniversaryHomeView()
                        }
                        hubLink("习惯与待办", "打卡连续天数 · 待办清单", .habits) {
                            HabitsTodosHomeView()
                        }
                        hubLink("二维码助手", "扫码 · 生成 · 智能跳转", .qrAssistant) {
                            QRAssistantHomeView()
                        }
                        hubLink("翻译器", "Sub2API · Google · 多引擎", .translator) {
                            TranslatorHomeView()
                        }
                        hubLink("快递查询", "单号本机管理 · 跳转查询", .express) {
                            ExpressHomeView()
                        }
                        hubLink("油价 / 汇率 / 金价", "国际参考行情", .market) {
                            MarketQuotesHomeView()
                        }
                    }

                    section("资讯", symbol: "newspaper.fill") {
                        hubLink("RSS 阅读器", "多源订阅 · 下拉刷新", .rss) {
                            RSSHomeView()
                        }
                        hubLink("财联社电报", "实时电报 · 本地缓存", .clsNews) {
                            CLSNewsHomeView()
                        }
                    }

                    section("监控", symbol: "waveform.path.ecg") {
                        hubLink("监控中心", "Sub2 管理 · Cloudflare（点标题切换）", .sub2) {
                            MonitorShellView()
                        }
                        hubLink("服务健康总览", "一键探测全部已配置服务", .health) {
                            ServiceHealthHomeView()
                        }
                        hubLink("Komari", settings.komariBaseURL, .komari) {
                            KomariHomeView()
                        }
                        hubLink("IP 检测", "出口 IP · 分流/代理启发式", .ipCheck) {
                            IPCheckHomeView()
                        }
                    }

                    section("订阅与节点", symbol: "link") {
                        hubLink("SublinkX", settings.sublinkBaseURL, .sublink) {
                            SublinkHomeView()
                        }
                    }

                    section("下载", symbol: "arrow.down.circle.fill") {
                        hubLink("视频下载", "YouTube · 抖音（页内切换）", .youtube) {
                            DownloadHomeView(isTabSelected: true)
                        }
                    }

                    section("直播", symbol: "play.tv.fill") {
                        Button {
                            selectedTab = .live
                        } label: {
                            AppNavRow(
                                title: "多平台直播",
                                subtitle: "虎牙/斗鱼/抖音/快手 · 关注搜索",
                                brand: .live
                            )
                            .appCard()
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.98))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(AppSurfaceBackground(accent: Color.accentColor))
            .navigationTitle("服务")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: title, systemImage: symbol)
            VStack(spacing: 10) {
                content()
            }
        }
    }

    private func hubLink<Destination: View>(
        _ title: String,
        _ subtitle: String,
        _ brand: ServiceBrand,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            AppNavRow(title: title, subtitle: subtitle, brand: brand)
                .appCard()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }
}
