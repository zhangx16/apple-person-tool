import SwiftUI

/// Hub for self-hosted services + local tools — card sections, recent, search.
struct ServicesHubView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var recent = LiveRecentStore.shared
    @State private var query = ""

    private struct HubItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let brand: ServiceBrand
        let section: String
        let open: () -> AnyView
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    searchBar

                    if query.isEmpty, !recent.brands().isEmpty {
                        section("最近使用", symbol: "clock.fill") {
                            ForEach(recent.brands(), id: \.rawValue) { brand in
                                if let item = allItems.first(where: { $0.brand == brand }) {
                                    hubButton(item)
                                }
                            }
                        }
                    }

                    ForEach(filteredSections, id: \.title) { sec in
                        section(sec.title, symbol: sec.symbol) {
                            ForEach(sec.items) { item in
                                hubButton(item)
                            }
                        }
                    }

                    if !query.isEmpty, filteredSections.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("没有匹配「\(query)」的工具")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
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

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索工具", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private struct SectionModel {
        let title: String
        let symbol: String
        let items: [HubItem]
    }

    private var filteredSections: [SectionModel] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sectionModels.compactMap { sec in
            let items = q.isEmpty
                ? sec.items
                : sec.items.filter {
                    $0.title.lowercased().contains(q)
                        || $0.subtitle.lowercased().contains(q)
                        || $0.section.lowercased().contains(q)
                }
            guard !items.isEmpty else { return nil }
            return SectionModel(title: sec.title, symbol: sec.symbol, items: items)
        }
    }

    private var allItems: [HubItem] {
        sectionModels.flatMap(\.items)
    }

    private var sectionModels: [SectionModel] {
        [
            SectionModel(title: "效率", symbol: "bolt.fill", items: [
                item("quickActions", "快捷动作中心", "剪贴板 / 链接 / 单号智能分流", .quickActions) {
                    AnyView(QuickActionsHomeView())
                },
                item("clipboard", "剪贴板工具箱", "历史 · 验证码 · 动作推荐", .clipboard) {
                    AnyView(ClipboardHomeView())
                },
                item("password", "密码生成器", "本地随机 · 强度提示", .password) {
                    AnyView(PasswordGeneratorHomeView())
                }
            ]),
            SectionModel(title: "生活", symbol: "heart.fill", items: [
                item("anniversary", "纪念日", "生日 · 倒计时 · 本地提醒", .anniversary) {
                    AnyView(AnniversaryHomeView())
                },
                item("habits", "习惯与待办", "打卡连续天数 · 待办清单", .habits) {
                    AnyView(HabitsTodosHomeView())
                },
                item("qr", "二维码助手", "扫码 · 生成 · 智能跳转", .qrAssistant) {
                    AnyView(QRAssistantHomeView())
                },
                item("translator", "翻译器", "Sub2API · Google · 多引擎", .translator) {
                    AnyView(TranslatorHomeView())
                },
                item("express", "快递查询", "单号本机管理 · 跳转查询", .express) {
                    AnyView(ExpressHomeView())
                },
                item("market", "油价 / 汇率 / 金价", "国际参考行情", .market) {
                    AnyView(MarketQuotesHomeView())
                }
            ]),
            SectionModel(title: "资讯", symbol: "newspaper.fill", items: [
                item("rss", "RSS 阅读器", "多源订阅 · 下拉刷新", .rss) {
                    AnyView(RSSHomeView())
                },
                item("cls", "财联社电报", "实时电报 · 本地缓存", .clsNews) {
                    AnyView(CLSNewsHomeView())
                }
            ]),
            SectionModel(title: "监控", symbol: "waveform.path.ecg", items: [
                item("monitor", "监控中心", "Sub2 管理 · Cloudflare（点标题切换）", .sub2) {
                    AnyView(MonitorShellView())
                },
                item("health", "服务健康总览", "一键探测全部已配置服务", .health) {
                    AnyView(ServiceHealthHomeView())
                },
                item("komari", "Komari", settings.komariBaseURL, .komari) {
                    AnyView(KomariHomeView())
                },
                item("ip", "IP 检测", "出口 IP · 分流/代理启发式", .ipCheck) {
                    AnyView(IPCheckHomeView())
                }
            ]),
            SectionModel(title: "订阅与节点", symbol: "link", items: [
                item("sublink", "SublinkX", settings.sublinkBaseURL, .sublink) {
                    AnyView(SublinkHomeView())
                }
            ]),
            SectionModel(title: "下载", symbol: "arrow.down.circle.fill", items: [
                item("download", "视频下载", "YouTube · 抖音（页内切换）", .youtube) {
                    AnyView(DownloadHomeView(isTabSelected: true))
                }
            ]),
            SectionModel(title: "直播", symbol: "play.tv.fill", items: [
                HubItem(
                    id: "live",
                    title: "多平台直播",
                    subtitle: "打开底部「直播」Tab · 关注与搜索",
                    brand: .live,
                    section: "直播",
                    open: { AnyView(EmptyView()) }
                )
            ])
        ]
    }

    private func item(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ brand: ServiceBrand,
        @ViewBuilder dest: @escaping () -> AnyView
    ) -> HubItem {
        HubItem(id: id, title: title, subtitle: subtitle, brand: brand, section: "", open: dest)
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

    @ViewBuilder
    private func hubButton(_ item: HubItem) -> some View {
        if item.brand == .live {
            Button {
                recent.record(.live)
                selectedTab = .live
            } label: {
                AppNavRow(title: item.title, subtitle: item.subtitle, brand: item.brand)
                    .appCard()
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))
        } else {
            NavigationLink {
                item.open()
                    .onAppear { recent.record(item.brand) }
            } label: {
                AppNavRow(title: item.title, subtitle: item.subtitle, brand: item.brand)
                    .appCard()
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))
        }
    }
}
