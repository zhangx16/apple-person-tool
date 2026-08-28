import SwiftUI

struct DeliveryDashboardView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var showsAdd = false
    @State private var showsCompleted = false
    private var active: [Parcel] { store.parcels.filter { $0.bucket == .active }.sorted { $0.progress > $1.progress } }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                if active.isEmpty { ContentUnavailableView("暂无在途快递", systemImage: "box.truck", description: Text("绑定平台账号并同步，或手动添加运单")) }
                ForEach(active) { parcel in ParcelCard(parcel: parcel) }
            }
            Button { showsCompleted = true } label: { Label("已完成 \(store.parcels.filter { $0.bucket == .completed }.count)", systemImage: "checkmark.circle.fill").padding(.horizontal, 18).padding(.vertical, 12).background(.ultraThinMaterial, in: Capsule()).shadow(radius: 8, y: 4) }.padding(20)
        }
        .navigationTitle("快递助手")
        .refreshable { await store.refreshActive() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { NavigationLink { AccountBindingView() } label: { Image(systemName: "person.crop.circle.badge.plus") } }
            ToolbarItem(placement: .topBarTrailing) { Button { showsAdd = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $showsAdd) { AddParcelView() }
        .sheet(isPresented: $showsCompleted) { NavigationStack { CompletedPanelView() } }
    }
}

private struct ParcelCard: View {
    @EnvironmentObject private var store: ParcelStore
    let parcel: Parcel
    var body: some View {
        NavigationLink { ParcelDetailView(id: parcel.id) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack { Image(systemName: "shippingbox.fill").foregroundStyle(.orange); Text(parcel.title).font(.headline).lineLimit(1); Spacer(); Text(parcel.statusText).font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                Text(parcel.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                ProgressView(value: parcel.progress).tint(.orange)
                HStack { Text(parcel.carrierName); Text(parcel.number).monospaced(); Spacer(); if parcel.isWatching { Image(systemName: "bell.fill").foregroundStyle(.orange) } }.font(.caption2).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }
        .swipeActions(edge: .leading) { Button { store.setWatching(parcel.id, !parcel.isWatching) } label: { Label(parcel.isWatching ? "取消跟踪" : "跟踪", systemImage: "bell") }.tint(.orange) }
        .swipeActions { Button(role: .destructive) { store.delete(parcel.id) } label: { Label("移除", systemImage: "trash") } }
    }
}

struct CompletedPanelView: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var bucket = ParcelBucket.completed; @State private var search = ""
    private var results: [Parcel] { store.parcels.filter { $0.bucket == bucket && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.number.contains(search)) } }
    var body: some View { List {
        Picker("分区", selection: $bucket) { Text("已完成").tag(ParcelBucket.completed); Text("异常包裹").tag(ParcelBucket.abnormal) }.pickerStyle(.segmented)
        ForEach(results) { ParcelCard(parcel: $0) }
        if results.isEmpty { ContentUnavailableView("暂无内容", systemImage: bucket.icon) }
    }.navigationTitle("\(bucket.rawValue) · \(results.count) 件").searchable(text: $search).toolbar { Button("完成") { dismiss() } } }
}
