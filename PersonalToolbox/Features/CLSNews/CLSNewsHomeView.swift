import SwiftUI
import UIKit

/// 财联社电报列表（参考 riccilnl 财联社.scripting）。
struct CLSNewsHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = CLSNewsViewModel()
    @State private var showSourceSettings = false
    @State private var toast: String?

    private let accent = CLSAccent.color

    var body: some View {
        Group {
            if viewModel.items.isEmpty && viewModel.isLoading {
                ProgressView("加载电报…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView {
                    Label("暂无电报", systemImage: "newspaper")
                } description: {
                    Text(viewModel.statusLine.isEmpty ? "下拉刷新或检查 RSS 源" : viewModel.statusLine)
                } actions: {
                    Button("重新加载") {
                        Task { await viewModel.load(settings: settings, force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                }
            } else {
                List {
                    if !viewModel.statusLine.isEmpty {
                        Section {
                            Text(viewModel.statusLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(viewModel.items) { item in
                            CLSNewsRow(item: item) {
                                UIPasteboard.general.string = item.displayText
                                flashToast("已复制")
                                Haptics.success()
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = item.displayText
                                    flashToast("已复制")
                                    Haptics.success()
                                } label: {
                                    Label("复制原文", systemImage: "doc.on.doc")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppSurfaceBackground(accent: Color.accentColor))
        .navigationTitle("财联社电报")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .clsNews, title: "财联社")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await viewModel.load(settings: settings, force: true) }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    Button {
                        showSourceSettings = true
                    } label: {
                        Label("RSS 源设置", systemImage: "link")
                    }
                    Button(role: .destructive) {
                        Task {
                            await viewModel.clearCache()
                            await viewModel.load(settings: settings, force: true)
                        }
                    } label: {
                        Label("清除缓存并刷新", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable {
            await viewModel.load(settings: settings, force: true)
        }
        .task {
            await viewModel.load(settings: settings, force: false)
        }
        .sheet(isPresented: $showSourceSettings) {
            NavigationStack {
                CLSSourceSettingsView()
                    .environmentObject(settings)
            }
            .presentationDetents([.medium])
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.92), in: Capsule())
                    .padding(.top, 8)
            }
        }
        .animation(AppleTheme.preferredSnappy, value: toast)
    }

    private func flashToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }
}

// MARK: - Row

struct CLSNewsRow: View {
    let item: CLSNewsItem
    var onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.timeLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(CLSAccent.color)
                    .frame(width: 40, alignment: .leading)
                Text(item.displayText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.timeLabel)，\(item.displayText)")
        .accessibilityHint("轻点复制")
    }
}

// MARK: - Source settings

struct CLSSourceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                TextField("RSS / Atom URL", text: $draft, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("电报源")
            } footer: {
                Text("默认使用 pyrsshub 的 cls/telegraph。可改为自建 RSSHub：…/cls/telegraph")
            }

            Section {
                Button("恢复默认源") {
                    draft = CLSNewsParsing.defaultFeedURL
                }
            }
        }
        .navigationTitle("RSS 源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    settings.clsFeedURL = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            draft = settings.clsFeedURL.isEmpty
                ? CLSNewsParsing.defaultFeedURL
                : settings.clsFeedURL
        }
    }
}

// MARK: - ViewModel

@MainActor
final class CLSNewsViewModel: ObservableObject {
    @Published var items: [CLSNewsItem] = []
    @Published var isLoading = false
    @Published var statusLine = ""

    private let service = CLSNewsService.shared

    func load(settings: AppSettings, force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        let feed = settings.clsFeedURL
        let result = await service.fetch(feedURL: feed, forceRefresh: force)
        items = result.items
        var parts: [String] = []
        if result.fromCache {
            parts.append("缓存")
        } else {
            parts.append("已更新")
        }
        if let t = result.lastUpdated {
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            parts.append(f.string(from: t))
        }
        if let err = result.errorMessage, result.fromCache {
            parts.append("网络失败已回退")
        } else if let err = result.errorMessage, items.isEmpty {
            parts.append(err)
        }
        statusLine = parts.joined(separator: " · ")
        if !result.items.isEmpty, !result.fromCache {
            Haptics.success()
        } else if result.items.isEmpty {
            Haptics.error()
        }
    }

    func clearCache() async {
        await service.clearCache()
    }
}
