import SwiftUI
import UIKit

/// Proxy / node scenario pack: probe egress + media + latency, save profiles.
struct ProxyNodePackView: View {
    @StateObject private var store = ProxyNodeProfileStore.shared
    @State private var name = ""
    @State private var includeMedia = true
    @State private var latencyHost = "www.google.com"
    @State private var isProbing = false
    @State private var error: String?
    @State private var last: ProxyNodeProfile?

    var body: some View {
        List {
            Section {
                Text("换节点后一键探测：当前出口 IP、风险画像、流媒体可用性、目标站延迟，并保存为节点档案。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("探测") {
                TextField("档案名称（可选）", text: $name)
                TextField("延迟探测主机", text: $latencyHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("包含流媒体 / AI", isOn: $includeMedia)
                Button {
                    Task { await runProbe() }
                } label: {
                    if isProbing {
                        ProgressView()
                    } else {
                        Label("开始探测并保存", systemImage: "bolt.horizontal.circle.fill")
                    }
                }
                .disabled(isProbing)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if let last {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近结果：\(last.name)").font(.subheadline.weight(.semibold))
                        Text(last.subtitle).font(.caption).foregroundStyle(.secondary)
                        Text(last.mediaSummary).font(.caption2).foregroundStyle(.tertiary)
                        Text(last.notes).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            if store.items.count >= 2 {
                Section("最近两次对比") {
                    let a = store.items[0]
                    let b = store.items[1]
                    LabeledContent("出口 IP") {
                        Text(a.egressIP == b.egressIP ? "相同 \(a.egressIP)" : "\(b.egressIP) → \(a.egressIP)")
                            .font(.caption)
                            .foregroundStyle(a.egressIP == b.egressIP ? Color.secondary : Color.orange)
                    }
                    LabeledContent("风险") {
                        Text("\(b.riskValue) → \(a.riskValue)")
                            .font(.caption.monospacedDigit())
                    }
                    LabeledContent("流媒体") {
                        Text(a.mediaSummary == b.mediaSummary ? "无变化" : "有变化")
                            .font(.caption)
                            .foregroundStyle(a.mediaSummary == b.mediaSummary ? Color.secondary : Color.orange)
                    }
                    if let la = a.latencyMs, let lb = b.latencyMs {
                        LabeledContent("延迟") {
                            Text("\(lb)ms → \(la)ms").font(.caption.monospacedDigit())
                        }
                    }
                }
            }

            Section("节点档案") {
                if store.items.isEmpty {
                    Text("暂无档案").foregroundStyle(.secondary)
                }
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name).font(.headline)
                            Spacer()
                            Text("风险 \(item.riskValue)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(item.riskValue >= 66 ? Color.red : (item.riskValue >= 33 ? Color.orange : Color.green))
                        }
                        Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        Text(item.mediaSummary).font(.caption2).foregroundStyle(.tertiary)
                        Text(item.vpnStatus + " · " + item.pathStatus)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.delete(id: item.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("节点探测包")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runProbe() async {
        isProbing = true
        error = nil
        defer { isProbing = false }
        let (profile, err) = await store.probeAndSave(
            name: name,
            includeMedia: includeMedia,
            latencyHost: latencyHost
        )
        if let profile {
            last = profile
            Haptics.success()
            ActivityEventStore.shared.log(.make(
                title: "节点探测",
                subtitle: profile.subtitle,
                systemImage: "network",
                tintHex: 0x0A84FF,
                route: "proxy"
            ))
        } else {
            error = err ?? "探测失败"
            Haptics.error()
        }
    }
}

// MARK: - Watch later home

struct WatchLaterHomeView: View {
    @StateObject private var store = WatchLaterStore.shared
    @State private var draft = ""

    var body: some View {
        List {
            Section("添加链接") {
                TextField("视频 / 网页 URL", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("加入稍后再看") {
                    store.add(url: draft, title: "", source: "manual")
                    draft = ""
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("列表") {
                if store.items.isEmpty {
                    Text("从剪贴板智能条或手动添加").foregroundStyle(.secondary)
                }
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(item.url).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .swipeActions {
                        Button {
                            AppDeepLinkStore.shared.openDownload(url: item.url)
                        } label: {
                            Label("下载", systemImage: "arrow.down.circle")
                        }
                        .tint(.green)
                        Button {
                            if let u = URL(string: item.url) {
                                UIApplication.shared.open(u)
                            }
                        } label: {
                            Label("打开", systemImage: "safari")
                        }
                        .tint(.blue)
                        Button(role: .destructive) {
                            store.delete(id: item.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            if !store.items.isEmpty {
                Section {
                    Button("清空全部", role: .destructive) { store.clear() }
                }
            }
        }
        .navigationTitle("稍后再看")
    }
}
