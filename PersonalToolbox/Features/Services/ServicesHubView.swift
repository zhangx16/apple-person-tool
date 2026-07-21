import SwiftUI

/// Hub for self-hosted services + local tools — 分区 chip + 2 列网格 + 最近使用 + 悬浮搜索。
struct ServicesHubView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var recent = LiveRecentStore.shared
    @State private var query = ""
    /// nil = 全部分区（LCSign 式可筛选 Tab/列表）
    @State private var selectedSection: String? = nil

    private struct HubItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let brand: ServiceBrand
        let section: String
        let open: () -> AnyView
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppleTheme.space5) {
                    // 悬浮搜索胶囊
                    FloatingSearchBar(text: $query, placeholder: "搜索工具、服务…")
                        .padding(.horizontal, AppleTheme.space4)
                        .padding(.top, AppleTheme.space2)

                    if query.isEmpty {
                        sectionFilterChips
                            .padding(.horizontal, AppleTheme.space4)

                        // 最近使用
                        if !recent.brands().isEmpty {
                            recentSection
                        }
                        // 全部分组网格（可按 chip 过滤）
                        ForEach(displaySections, id: \.title) { sec in
                            gridSection(sec)
                        }
                    } else {
                        // 搜索结果（列表样式，便于扫读）
                        searchResults
                    }
                }
                .padding(.bottom, AppleTheme.space8)
            }
            .background(AppSurfaceBackground(accent: Color.accentColor))
            .navigationTitle("服务")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    // MARK: - 分区筛选 chips

    private var sectionFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "全部",
                    systemImage: "square.grid.2x2",
                    isSelected: selectedSection == nil,
                    tint: .accentColor
                ) {
                    selectedSection = nil
                }
                ForEach(sectionModels, id: \.title) { sec in
                    FilterChip(
                        title: sec.title,
                        systemImage: sec.symbol,
                        isSelected: selectedSection == sec.title,
                        tint: .accentColor
                    ) {
                        selectedSection = sec.title
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var displaySections: [SectionModel] {
        guard let selectedSection else { return sectionModels }
        return sectionModels.filter { $0.title == selectedSection }
    }

    // MARK: - 最近使用

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: AppleTheme.space3) {
            AppSectionTitle(title: "最近使用", systemImage: "clock.fill")
                .padding(.horizontal, AppleTheme.space4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recent.brands(), id: \.rawValue) { brand in
                        if let item = allItems.first(where: { $0.brand == brand }) {
                            recentChip(item)
                        }
                    }
                }
                .padding(.horizontal, AppleTheme.space4)
            }
        }
    }

    @ViewBuilder
    private func recentChip(_ item: HubItem) -> some View {
        let label = HStack(spacing: 8) {
            ServiceBrandIcon(brand: item.brand, size: 28)
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            Capsule()
                .strokeBorder(AppStroke.highlight, lineWidth: 1)
        }
        .modifier(AppShadow.near())

        if item.brand == .live {
            Button {
                recent.record(.live)
                selectedTab = .live
            } label: {
                label
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))
        } else {
            NavigationLink {
                item.open()
                    .onAppear { recent.record(item.brand) }
            } label: {
                label
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))
        }
    }

    // MARK: - 网格分组

    @ViewBuilder
    private func gridSection(_ sec: SectionModel) -> some View {
        VStack(alignment: .leading, spacing: AppleTheme.space3) {
            AppSectionTitle(title: sec.title, systemImage: sec.symbol)
                .padding(.horizontal, AppleTheme.space4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(sec.items) { item in
                    gridCard(item)
                }
            }
            .padding(.horizontal, AppleTheme.space4)
        }
    }

    @ViewBuilder
    private func gridCard(_ item: HubItem) -> some View {
        let card = GridCard {
            VStack(alignment: .leading, spacing: AppleTheme.space3) {
                BrandIconBadge(brand: item.brand, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
        }

        if item.brand == .live {
            Button {
                recent.record(.live)
                selectedTab = .live
            } label: {
                card
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))
        } else {
            NavigationLink {
                item.open()
                    .onAppear { recent.record(item.brand) }
            } label: {
                card
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))
        }
    }

    // MARK: - 搜索结果

    @ViewBuilder
    private var searchResults: some View {
        if filteredSections.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "没有匹配结果",
                message: "没有找到「\(query)」相关的工具或服务。",
                pathHint: "试试换个关键词，或清空搜索浏览全部分区",
                actionTitle: "清空搜索",
                action: { query = "" }
            )
            .frame(minHeight: 320)
        } else {
            VStack(spacing: AppleTheme.space5) {
                ForEach(filteredSections, id: \.title) { sec in
                    VStack(alignment: .leading, spacing: AppleTheme.space3) {
                        AppSectionTitle(title: sec.title, systemImage: sec.symbol)
                            .padding(.horizontal, AppleTheme.space4)
                        VStack(spacing: 10) {
                            ForEach(sec.items) { item in
                                searchRow(item)
                            }
                        }
                        .padding(.horizontal, AppleTheme.space4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchRow(_ item: HubItem) -> some View {
        let row = AppNavRow(title: item.title, subtitle: item.subtitle, brand: item.brand)
            .appCard()

        if item.brand == .live {
            Button {
                recent.record(.live)
                selectedTab = .live
            } label: {
                row
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))
        } else {
            NavigationLink {
                item.open()
                    .onAppear { recent.record(item.brand) }
            } label: {
                row
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))
        }
    }

    // MARK: - Data

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
                item(
                    "sub2Monitor",
                    "Sub2 管理",
                    settings.isAdminConfigured ? "账号调度 · 用户 · 分组" : "未配置 Admin Token",
                    .sub2
                ) {
                    AnyView(MonitorHomeView())
                },
                item(
                    "cloudflare",
                    "Cloudflare",
                    settings.isCloudflareConfigured ? "用量 · 域名 · DNS" : "未配置 API Token",
                    .cloudflare
                ) {
                    AnyView(CloudflareHomeView())
                },
                item("health", "服务健康总览", "一键探测全部已配置服务", .health) {
                    AnyView(ServiceHealthHomeView())
                },
                item("komari", "Komari", settings.komariBaseURL, .komari) {
                    AnyView(KomariHomeView())
                },
                item("checkin", "签到中心", settings.isCheckinConfigured ? "GLaDOS / Emby / TG Bot 状态" : "未配置 · 设置里填写 Token", .checkin) {
                    AnyView(CheckinHomeView())
                },
                item("ip", "IP 检测", "IPSuper 风格聚合 · 风险画像 · 流媒体", .ipCheck) {
                    AnyView(IPCheckHomeView())
                }
            ]),
            SectionModel(title: "订阅与节点", symbol: "link", items: [
                item("sublink", "SublinkX", settings.sublinkBaseURL, .sublink) {
                    AnyView(SublinkHomeView())
                }
            ]),
            SectionModel(title: "下载", symbol: "arrow.down.circle.fill", items: [
                item("download", "视频下载", "YouTube / 抖音 / B站 · 同一入口", .youtube) {
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
        section: String = "",
        @ViewBuilder dest: @escaping () -> AnyView
    ) -> HubItem {
        HubItem(id: id, title: title, subtitle: subtitle, brand: brand, section: section, open: dest)
    }
}
