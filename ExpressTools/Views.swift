import SwiftUI

struct ParcelHomeView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var bucket = ParcelBucket.active
    @State private var search = ""
    @State private var showsAdd = false
    private var shown: [Parcel] { store.parcels.filter { $0.bucket == bucket && (search.isEmpty || $0.number.localizedCaseInsensitiveContains(search) || $0.title.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search)) } }

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    ForEach(ParcelBucket.allCases) { item in
                        Button { bucket = item } label: {
                            VStack(spacing: 5) { Image(systemName: item.icon); Text(item.rawValue).font(.caption.weight(.semibold)); Text("\(store.parcels.filter { $0.bucket == item }.count)").font(.title3.bold().monospacedDigit()) }.frame(maxWidth: .infinity).foregroundStyle(bucket == item ? .orange : .secondary)
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 8)
            }
            Section(bucket.rawValue) {
                if shown.isEmpty { ContentUnavailableView(search.isEmpty ? "暂无\(bucket.rawValue)包裹" : "没有匹配结果", systemImage: bucket.icon, description: Text("点击右上角添加运单")) }
                ForEach(shown) { parcel in
                    NavigationLink { ParcelDetailView(id: parcel.id) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "shippingbox.fill").foregroundStyle(.white).frame(width: 42, height: 42).background(.orange.gradient, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(parcel.title).font(.headline); Spacer(); if parcel.isWatching { Image(systemName: "bell.fill").foregroundStyle(.orange) } }
                                Text(parcel.number).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(parcel.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                ProgressView(value: parcel.progress).tint(parcel.bucket == .abnormal ? .red : .orange)
                            }
                        }.padding(.vertical, 4)
                    }
                    .swipeActions(edge: .leading) { Button { store.setWatching(parcel.id, !parcel.isWatching) } label: { Label(parcel.isWatching ? "取消关注" : "关注", systemImage: "bell") }.tint(.orange) }
                    .swipeActions { Button(role: .destructive) { store.delete(parcel.id) } label: { Label("删除", systemImage: "trash") } }
                }
            }
        }
        .navigationTitle("快递助手").searchable(text: $search, prompt: "搜索单号、备注或动态").refreshable { await store.refreshActive() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showsAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showsAdd) { AddParcelView() }
        .alert("提示", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("好") { store.message = nil } } message: { Text(store.message ?? "") }
    }
}

struct AddParcelView: View {
    @EnvironmentObject private var store: ParcelStore
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""; @State private var alias = ""; @State private var phone = ""
    var body: some View {
        NavigationStack { Form {
            Section("运单") { TextField("快递单号", text: $number).textInputAutocapitalization(.characters).autocorrectionDisabled(); TextField("包裹名称（可选）", text: $alias); TextField("手机后四位（顺丰等）", text: $phone).keyboardType(.numberPad) }
            if !number.isEmpty { Section("自动识别") { Label(CarrierCatalog.guess(number).1, systemImage: "shippingbox.fill") } }
        }.navigationTitle("添加包裹").navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("添加") { store.add(number: number, alias: alias, phone: phone); let id = store.parcels.first?.id; dismiss(); if let id { Task { await store.refresh(id) } } }.disabled(number.trimmingCharacters(in: .whitespaces).isEmpty) }
        }}
    }
}

struct ParcelDetailView: View {
    let id: UUID
    @EnvironmentObject private var store: ParcelStore
    private var parcel: Parcel? { store.parcels.first { $0.id == id } }
    var body: some View { List { if let parcel {
        Section("运单") { LabeledContent("单号", value: parcel.number); LabeledContent("承运商", value: parcel.carrierName); LabeledContent("状态", value: parcel.statusText); if let code = parcel.pickupCode { LabeledContent("取件码", value: code) }; if let date = parcel.estimatedDate { LabeledContent("预计送达", value: date.formatted(date: .abbreviated, time: .omitted)) }; ProgressView(value: parcel.progress) }
        Section("物流轨迹") { if parcel.events.isEmpty { ContentUnavailableView("暂无轨迹", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }; ForEach(Array(parcel.events.enumerated()), id: \.element.id) { index, event in HStack(alignment: .top, spacing: 12) { Circle().fill(index == 0 ? .orange : .gray.opacity(0.35)).frame(width: index == 0 ? 12 : 8, height: index == 0 ? 12 : 8); VStack(alignment: .leading, spacing: 4) { Text(event.time).font(.caption).foregroundStyle(.secondary); Text(event.description); if let location = event.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary) } } }.padding(.vertical, 4) } }
    }}.navigationTitle("物流详情").toolbar { Button { Task { await store.refresh(id) } } label: { if store.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.disabled(store.isRefreshing) }.task { if parcel?.events.isEmpty == true { await store.refresh(id) } } }
}

struct ParcelCalendarView: View {
    @EnvironmentObject private var store: ParcelStore
    @State private var selected = Date()
    private var arrivals: [Parcel] { store.parcels.filter { guard let date = $0.estimatedDate else { return false }; return Calendar.current.isDate(date, inSameDayAs: selected) } }
    var body: some View { List { Section { DatePicker("日期", selection: $selected, displayedComponents: .date).datePickerStyle(.graphical) }; Section("预计到达") { if arrivals.isEmpty { Text("当天暂无预计到达包裹").foregroundStyle(.secondary) }; ForEach(arrivals) { parcel in NavigationLink(parcel.title) { ParcelDetailView(id: parcel.id) } } } }.navigationTitle("快递日历") }
}

struct SettingsView: View {
    @StateObject private var repository = AppRepository.shared
    @State private var customer = Secrets.get("customer"); @State private var key = Secrets.get("key")
    @State private var aiBase = Secrets.get("ai.base"); @State private var aiKey = Secrets.get("ai.key"); @State private var aiModel = Secrets.get("ai.model")
    @State private var saved = false; @State private var showsSchedule = false; @State private var addressLabel = "家"; @State private var address = ""
    var body: some View { Form {
        Section("平台连接") { NavigationLink { AccountBindingView() } label: { LabeledContent("多源账号", value: "\(repository.accounts.count) 个") } }
        Section("我的地址") {
            ForEach(repository.addresses) { item in VStack(alignment: .leading) { Text(item.label).font(.headline); Text(item.address).font(.caption).foregroundStyle(.secondary) }.swipeActions { Button(role: .destructive) { repository.addresses.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") } } }
            TextField("名称", text: $addressLabel); TextField("详细地址（用于 AI 预计到达）", text: $address)
            Button("添加地址") { guard !address.isEmpty else { return }; repository.addresses.append(HomeAddress(label: addressLabel, address: address)); address = "" }.disabled(address.isEmpty)
        }
        Section("快递轮询") { Picker("后台刷新", selection: $repository.pollingMinutes) { Text("关闭").tag(0); Text("15 分钟").tag(15); Text("30 分钟").tag(30); Text("1 小时").tag(60) }; Text("iOS 会根据系统策略安排后台刷新，实际时间可能晚于所选间隔。").font(.caption).foregroundStyle(.secondary) }
        Section("AI 云雀与日报") {
            TextField("API Base URL", text: $aiBase).textInputAutocapitalization(.never).autocorrectionDisabled(); SecureField("API Key", text: $aiKey); TextField("模型", text: $aiModel)
            NavigationLink { ReportSchedulesView() } label: { LabeledContent("定时日报", value: "\(repository.schedules.filter(\.enabled).count) 项") }
        }
        Section("快递100 实时查询") { TextField("Customer", text: $customer).textInputAutocapitalization(.never).autocorrectionDisabled(); SecureField("授权 Key", text: $key); Button("安全保存") { Secrets.set(customer.trimmingCharacters(in: .whitespacesAndNewlines), for: "customer"); Secrets.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: "key"); saved = true } }
        Section { Button("保存全部设置") { Secrets.set(customer.trimmingCharacters(in: .whitespacesAndNewlines), for: "customer"); Secrets.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: "key"); Secrets.set(aiBase.trimmingCharacters(in: .whitespacesAndNewlines), for: "ai.base"); Secrets.set(aiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "ai.key"); Secrets.set(aiModel.trimmingCharacters(in: .whitespacesAndNewlines), for: "ai.model"); saved = true }.frame(maxWidth: .infinity) }
        Section("隐私") { Label("密钥仅保存在本机 Keychain", systemImage: "lock.shield.fill"); Text("运单数据保存在 App 沙盒，不包含广告与分析 SDK。").font(.caption).foregroundStyle(.secondary) }
        Section("说明") { Text("本项目与各快递公司及快递100无隶属关系。接口使用需自行申请合法授权，平台数据源可通过后续 Provider 扩展接入。") }
    }.navigationTitle("设置").alert("已保存", isPresented: $saved) { Button("好", role: .cancel) {} } }
}

struct ReportSchedulesView: View {
    @StateObject private var repository = AppRepository.shared
    var body: some View { List {
        ForEach($repository.schedules) { $schedule in
            VStack(alignment: .leading, spacing: 8) { Toggle(isOn: $schedule.enabled) { Text(String(format: "%02d:%02d", schedule.hour, schedule.minute)).font(.title2.monospacedDigit().bold()) }; Picker("重复", selection: $schedule.rule) { ForEach(ReportSchedule.RepeatRule.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }
        }.onDelete { repository.schedules.remove(atOffsets: $0) }
    }.navigationTitle("定时日报").toolbar { Button { repository.schedules.append(ReportSchedule()) } label: { Image(systemName: "plus") } } }
}
