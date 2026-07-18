import SwiftUI

/// Hub for self-hosted services + local tools.
struct ServicesHubView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            List {
                Section("效率") {
                    NavigationLink {
                        QuickActionsHomeView()
                    } label: {
                        sfHubLabel(
                            title: "快捷动作中心",
                            subtitle: "剪贴板 / 链接 / 单号智能分流",
                            systemImage: "bolt.horizontal.circle.fill"
                        )
                    }

                    NavigationLink {
                        ClipboardHomeView()
                    } label: {
                        sfHubLabel(
                            title: "剪贴板工具箱",
                            subtitle: "历史 · 验证码 · 动作推荐",
                            systemImage: "doc.on.clipboard.fill"
                        )
                    }

                    NavigationLink {
                        PasswordGeneratorHomeView()
                    } label: {
                        sfHubLabel(
                            title: "密码生成器",
                            subtitle: "本地随机 · 强度提示",
                            systemImage: "key.fill"
                        )
                    }
                }

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

                    NavigationLink {
                        HabitsTodosHomeView()
                    } label: {
                        sfHubLabel(
                            title: "习惯与待办",
                            subtitle: "打卡连续天数 · 待办清单",
                            systemImage: "checklist"
                        )
                    }

                    NavigationLink {
                        QRAssistantHomeView()
                    } label: {
                        hubLabel(
                            title: "二维码助手",
                            subtitle: "扫码 · 生成 · 智能跳转",
                            brand: .qrAssistant
                        )
                    }

                    NavigationLink {
                        TranslatorHomeView()
                    } label: {
                        hubLabel(
                            title: "翻译器",
                            subtitle: "Sub2API · Google · 多引擎",
                            brand: .translator
                        )
                    }

                    NavigationLink {
                        ExpressHomeView()
                    } label: {
                        sfHubLabel(
                            title: "快递查询",
                            subtitle: "单号本机管理 · 跳转查询",
                            systemImage: "shippingbox.fill"
                        )
                    }

                    NavigationLink {
                        MarketQuotesHomeView()
                    } label: {
                        sfHubLabel(
                            title: "油价 / 汇率 / 金价",
                            subtitle: "国际参考行情",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                    }
                }

                Section("资讯") {
                    NavigationLink {
                        RSSHomeView()
                    } label: {
                        sfHubLabel(
                            title: "RSS 阅读器",
                            subtitle: "多源订阅 · 下拉刷新",
                            systemImage: "dot.radiowaves.up.forward"
                        )
                    }

                    NavigationLink {
                        CLSNewsHomeView()
                    } label: {
                        hubLabel(
                            title: "财联社电报",
                            subtitle: "实时电报 · 本地缓存",
                            brand: .clsNews
                        )
                    }
                }

                Section("监控") {
                    NavigationLink {
                        MonitorShellView()
                    } label: {
                        hubLabel(
                            title: "监控中心",
                            subtitle: "Sub2 管理 · Cloudflare（点标题切换）",
                            brand: .sub2
                        )
                    }
                    .accessibilityLabel("监控中心")

                    NavigationLink {
                        ServiceHealthHomeView()
                    } label: {
                        sfHubLabel(
                            title: "服务健康总览",
                            subtitle: "一键探测全部已配置服务",
                            systemImage: "heart.text.square.fill"
                        )
                    }

                    NavigationLink {
                        KomariHomeView()
                    } label: {
                        hubLabel(
                            title: "Komari",
                            subtitle: settings.komariBaseURL,
                            brand: .komari
                        )
                    }

                    NavigationLink {
                        IPCheckHomeView()
                    } label: {
                        hubLabel(
                            title: "IP 检测",
                            subtitle: "出口 IP · 分流/代理启发式",
                            brand: .ipCheck
                        )
                    }
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
                }

                Section("下载") {
                    NavigationLink {
                        DownloadHomeView(isTabSelected: true)
                    } label: {
                        hubLabel(
                            title: "视频下载",
                            subtitle: "YouTube · 抖音（页内切换）",
                            brand: .youtube
                        )
                    }
                    .accessibilityLabel("视频下载")
                }

                Section("直播") {
                    Text("底部「直播」Tab：B站 · 虎牙 · 斗鱼 · 抖音 · 快手：分区 · 弹幕(B站/虎牙/斗鱼/抖音) · 快手推荐。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private func sfHubLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
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
