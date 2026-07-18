import SwiftUI

/// Hub for self-hosted services: SublinkX, Komari, yt-dlp download.
struct ServicesHubView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            List {
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
                }

                Section("Sub2API") {
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
