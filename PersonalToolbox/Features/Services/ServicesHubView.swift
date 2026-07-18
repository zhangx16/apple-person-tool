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
                            systemImage: "link.circle.fill",
                            color: .blue
                        )
                    }
                    .accessibilityLabel("SublinkX 订阅管理")

                    NavigationLink {
                        KomariHomeView()
                    } label: {
                        hubLabel(
                            title: "Komari",
                            subtitle: settings.komariBaseURL,
                            systemImage: "server.rack",
                            color: .teal
                        )
                    }
                    .accessibilityLabel("Komari 服务器探针")
                }

                Section("媒体") {
                    Button {
                        selectedTab = .download
                    } label: {
                        hubLabel(
                            title: "视频下载",
                            subtitle: settings.ytBaseURL,
                            systemImage: "arrow.down.circle.fill",
                            color: .orange
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

    private func hubLabel(title: String, subtitle: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
