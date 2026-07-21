import SwiftUI

// MARK: - Clipboard (CAIS-class)

struct ClipboardHomeView: View {
    @ObservedObject private var store = ClipboardStore.shared
    @State private var draft = ""
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppleTheme.space5) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("手动添加文本", text: $draft, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    HStack(spacing: 10) {
                        Button {
                            store.addManual(draft)
                            draft = ""
                            Haptics.light()
                        } label: {
                            Label("添加", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

                        Button {
                            if store.capturePasteboard() != nil {
                                toast = "已从剪贴板捕获"
                                Haptics.success()
                            } else {
                                toast = "剪贴板为空或与上一条相同"
                                Haptics.error()
                            }
                        } label: {
                            Label("捕获", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    Text("保存历史并可识别链接 / 快递单号 / 验证码。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .appCardV2()

                if let toast {
                    StatusPill(title: toast, color: .accentColor, systemImage: "info.circle.fill")
                        .padding(.horizontal, 4)
                }

                AppSectionTitle(title: "历史 (\(store.items.count))", systemImage: "clock")
                if store.items.isEmpty {
                    EmptyStateView(
                        symbol: "doc.on.clipboard",
                        title: "还没有记录",
                        message: "从系统剪贴板捕获，或手动添加文本。",
                        pathHint: "服务 → 剪贴板工具箱",
                        actionTitle: "从剪贴板捕获",
                        action: {
                            if store.capturePasteboard() != nil {
                                toast = "已从剪贴板捕获"
                                Haptics.success()
                            } else {
                                toast = "剪贴板为空或与上一条相同"
                                Haptics.error()
                            }
                        }
                    )
                    .frame(minHeight: 220)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.items) { item in
                            NavigationLink {
                                ClipboardDetailView(item: item)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.preview)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .appCard()
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.98))
                            .contextMenu {
                                Button {
                                    store.copyToPasteboard(item.text)
                                    Haptics.success()
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    store.delete(id: item.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(AppSurfaceBackground(accent: ServiceBrand.clipboard.tint))
        .navigationTitle("剪贴板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空", role: .destructive) { store.clear() }
                    .disabled(store.items.isEmpty)
            }
        }
        .onAppear { _ = store.capturePasteboard() }
    }
}

struct ClipboardDetailView: View {
    let item: ClipboardItem
    @ObservedObject private var store = ClipboardStore.shared

    private var suggestions: [AppActionPayload] {
        ActionRouter.suggest(from: item.text)
    }

    var body: some View {
        List {
            Section("内容") {
                Text(item.text)
                    .textSelection(.enabled)
                Button {
                    store.copyToPasteboard(item.text)
                    Haptics.success()
                } label: { Label("复制全文", systemImage: "doc.on.doc") }
                if let code = ActionRouter.extractVerificationCode(from: item.text) {
                    Button {
                        store.copyToPasteboard(code)
                        Haptics.success()
                    } label: { Label("复制验证码 \(code)", systemImage: "number") }
                }
            }
            if !suggestions.isEmpty {
                Section("快捷动作") {
                    ForEach(suggestions, id: \.action) { payload in
                        NavigationLink {
                            QuickActionRunnerView(payload: payload)
                        } label: {
                            Label(payload.action.title, systemImage: payload.action.systemImage)
                        }
                    }
                }
            }
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Quick Actions

struct QuickActionsHomeView: View {
    @State private var input = ""
    @ObservedObject private var clipboard = ClipboardStore.shared

    private var suggestions: [AppActionPayload] {
        ActionRouter.suggest(from: input)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppleTheme.space5) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("输入")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("粘贴链接、单号或任意文本", text: $input, axis: .vertical)
                        .lineLimit(3...8)
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        if let item = clipboard.capturePasteboard() {
                            input = item.text
                            Haptics.light()
                        }
                    } label: {
                        Label("填入剪贴板", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(GhostButtonStyle())
                    Text("根据内容推荐：下载、翻译、快递、RSS 等。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .appCardV2()

                AppSectionTitle(title: "推荐动作", systemImage: "bolt.fill")
                if suggestions.isEmpty {
                    Text("输入内容后显示可执行动作")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, payload in
                            NavigationLink {
                                QuickActionRunnerView(payload: payload)
                            } label: {
                                AppNavRow(
                                    title: payload.action.title,
                                    subtitle: "点按执行",
                                    systemImage: payload.action.systemImage,
                                    tint: .accentColor
                                )
                                .appCard()
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.98))
                        }
                    }
                }

                AppSectionTitle(title: "全部工具", systemImage: "square.grid.2x2")
                VStack(spacing: 10) {
                    toolLink("剪贴板", "doc.on.clipboard", Color(hex: 0x0A84FF)) { ClipboardHomeView() }
                    toolLink("服务健康", "heart.text.square", Color(hex: 0xFF375F)) { ServiceHealthHomeView() }
                    toolLink("RSS 阅读", "dot.radiowaves.up.forward", Color(hex: 0xFF9500)) { RSSHomeView() }
                    toolLink("习惯与待办", "checklist", Color(hex: 0x30D158)) { HabitsTodosHomeView() }
                    toolLink("行情", "chart.line.uptrend.xyaxis", Color(hex: 0x34C759)) { MarketQuotesHomeView() }
                    toolLink("快递", "shippingbox", Color(hex: 0xAC8E68)) { ExpressHomeView() }
                    toolLink("密码生成", "key.fill", Color(hex: 0xBF5AF2)) { PasswordGeneratorHomeView() }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(AppSurfaceBackground(accent: ServiceBrand.quickActions.tint))
        .navigationTitle("快捷动作")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if input.isEmpty, let item = clipboard.capturePasteboard() {
                input = item.text
            }
        }
    }

    private func toolLink<V: View>(
        _ title: String,
        _ icon: String,
        _ tint: Color,
        @ViewBuilder dest: () -> V
    ) -> some View {
        NavigationLink {
            dest()
        } label: {
            AppNavRow(title: title, subtitle: "打开工具", systemImage: icon, tint: tint)
                .appCard()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }
}

/// Executes / routes a payload into the right feature UI.
struct QuickActionRunnerView: View {
    let payload: AppActionPayload
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            switch payload.action {
            case .downloadYouTube:
                DownloadJumpView(mode: .youtube, prefill: payload.url ?? payload.text)
            case .downloadDouyin:
                DownloadJumpView(mode: .douyin, prefill: payload.url ?? payload.text)
            case .translate:
                TranslatorJumpView(prefill: payload.text)
            case .openClipboard:
                ClipboardHomeView()
            case .openRSS:
                RSSHomeView(initialURL: payload.url)
            case .openHabits, .openTodos:
                HabitsTodosHomeView(initialTab: payload.action == .openTodos ? 1 : 0)
            case .openMarket:
                MarketQuotesHomeView()
            case .openExpress:
                ExpressHomeView(prefill: payload.url ?? payload.text)
            case .openPassword:
                PasswordGeneratorHomeView()
            case .openHealth:
                ServiceHealthHomeView()
            case .openQuickActions:
                QuickActionsHomeView()
            case .scanQRHint:
                QRAssistantHomeView()
            case .openSettings:
                Text("请切换到「设置」Tab").padding()
            }
        }
        .environmentObject(settings)
    }
}

/// Lightweight jump: show prefilled text + instructions (Download tab is separate).
struct DownloadJumpView: View {
    let mode: DownloadProject
    let prefill: String?
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var clipboard = ClipboardStore.shared

    var body: some View {
        List {
            Section {
                Text(mode == .douyin ? "抖音本机下载" : "YouTube / yt-dlp 下载")
                if let prefill, !prefill.isEmpty {
                    Text(prefill).font(.footnote).textSelection(.enabled)
                    Button("复制链接到剪贴板") {
                        clipboard.copyToPasteboard(prefill)
                        Haptics.success()
                    }
                }
                NavigationLink {
                    DownloadHomeView(isTabSelected: true)
                } label: {
                    Label("打开下载页（\(mode.title)）", systemImage: "arrow.down.circle")
                }
            } footer: {
                Text("下载已并入「服务」；链接已复制，进入后粘贴即可。")
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings.downloadProjectRaw = mode.rawValue
            if let prefill, !prefill.isEmpty {
                clipboard.copyToPasteboard(prefill)
            }
        }
    }
}

struct TranslatorJumpView: View {
    let prefill: String?
    var body: some View {
        TranslatorHomeView()
            .onAppear {
                // Translator loads its own store; user can paste. Prefill via pasteboard.
                if let prefill, !prefill.isEmpty {
                    ClipboardStore.shared.copyToPasteboard(prefill)
                }
            }
    }
}

// MARK: - Service Health

struct ServiceHealthHomeView: View {
    @StateObject private var health = ServiceHealthService.shared

    var body: some View {
        List {
            Section {
                Button {
                    Task { await health.probeAll() }
                } label: {
                    if health.isProbing {
                        HStack {
                            ProgressView()
                            Text("检测中…")
                        }
                    } else {
                        Label("全部探测", systemImage: "bolt.horizontal.circle")
                    }
                }
                .disabled(health.isProbing)
                if let t = health.lastProbedAt {
                    Text("上次：\(t.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("服务") {
                ForEach(health.items) { item in
                    HStack(spacing: 12) {
                        ServiceBrandIcon(brand: item.brand, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.status.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: item.status))
                            if let ms = item.latencyMs {
                                Text("\(ms) ms").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("服务健康")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if health.items.allSatisfy({ $0.status == .unknown || $0.status == .skip }) {
                await health.probeAll()
            }
        }
    }

    private func color(for s: ServiceHealthItem.Status) -> Color {
        switch s {
        case .ok: return .green
        case .fail: return .red
        case .skip: return .secondary
        case .unknown: return .orange
        }
    }
}

// MARK: - RSS

struct RSSHomeView: View {
    var initialURL: String? = nil
    @StateObject private var store = RSSStore.shared
    @State private var showAdd = false
    @State private var newTitle = ""
    @State private var newURL = ""

    var body: some View {
        List {
            if let err = store.errorMessage {
                Section { Text(err).foregroundStyle(.red).font(.footnote) }
            }
            Section("条目") {
                if store.isLoading && store.entries.isEmpty {
                    ProgressView("加载中…")
                } else if store.entries.isEmpty {
                    Text("下拉刷新或添加订阅源").foregroundStyle(.secondary)
                } else {
                    ForEach(store.entries) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.title).font(.subheadline.weight(.semibold))
                            Text(e.feedTitle).font(.caption2).foregroundStyle(.secondary)
                            if !e.summary.isEmpty {
                                Text(e.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            if let link = e.link, let url = URL(string: link) {
                                Link("打开原文", destination: url).font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section("订阅源") {
                ForEach(store.sources) { s in
                    Toggle(isOn: Binding(
                        get: { s.enabled },
                        set: { _ in store.toggle(s.id) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(s.title)
                            Text(s.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { store.sources[$0].id }.forEach(store.removeSource)
                }
            }
        }
        .navigationTitle("RSS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isLoading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField("名称", text: $newTitle)
                    TextField("Feed URL", text: $newURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                .navigationTitle("添加订阅")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            store.addSource(
                                title: newTitle.isEmpty ? "订阅源" : newTitle,
                                url: newURL.isEmpty ? (initialURL ?? "") : newURL
                            )
                            showAdd = false
                            newTitle = ""
                            newURL = ""
                            Task { await store.refresh() }
                        }
                        .disabled((newURL.isEmpty && initialURL == nil))
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            if let initialURL, !initialURL.isEmpty {
                newURL = initialURL
            }
        }
    }
}

// MARK: - Habits & Todos

struct HabitsTodosHomeView: View {
    var initialTab: Int = 0
    @StateObject private var store = HabitTodoStore.shared
    @State private var tab: Int = 0
    @State private var habitDraft = ""
    @State private var todoDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("习惯").tag(0)
                Text("待办").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            List {
                if tab == 0 {
                    Section {
                        HStack {
                            TextField("新习惯", text: $habitDraft)
                            Button("添加") {
                                store.addHabit(title: habitDraft)
                                habitDraft = ""
                                Haptics.light()
                            }
                            .disabled(habitDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Section("今日") {
                        if store.habits.isEmpty {
                            Text("添加一个习惯开始打卡").foregroundStyle(.secondary)
                        } else {
                            ForEach(store.habits) { h in
                                Button {
                                    store.toggleHabitToday(h.id)
                                    Haptics.light()
                                } label: {
                                    HStack {
                                        Image(systemName: h.isDone() ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(h.isDone() ? Color.green : Color.secondary)
                                        VStack(alignment: .leading) {
                                            Text(h.title).foregroundStyle(.primary)
                                            Text("连续 \(h.streak) 天").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .onDelete { idx in
                                idx.map { store.habits[$0].id }.forEach(store.deleteHabit)
                            }
                        }
                    }
                } else {
                    Section {
                        HStack {
                            TextField("新待办", text: $todoDraft)
                            Button("添加") {
                                store.addTodo(title: todoDraft)
                                todoDraft = ""
                                Haptics.light()
                            }
                            .disabled(todoDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Section("未完成 (\(store.openTodos.count))") {
                        ForEach(store.openTodos) { t in
                            todoRow(t)
                        }
                    }
                    if !store.doneTodos.isEmpty {
                        Section("已完成") {
                            ForEach(store.doneTodos) { t in
                                todoRow(t)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .background(AppleTheme.canvas)
        .navigationTitle("习惯与待办")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tab = initialTab }
    }

    private func todoRow(_ t: TodoItem) -> some View {
        Button {
            store.toggleTodo(t.id)
            Haptics.light()
        } label: {
            HStack {
                Image(systemName: t.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(t.isDone ? Color.green : Color.secondary)
                Text(t.title)
                    .strikethrough(t.isDone)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .swipeActions {
            Button(role: .destructive) { store.deleteTodo(t.id) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - Market

struct MarketQuotesHomeView: View {
    @StateObject private var market = MarketQuotesService.shared

    var body: some View {
        List {
            if let err = market.errorMessage {
                Section { Text(err).foregroundStyle(.red).font(.footnote) }
            }
            Section {
                if market.isLoading && market.quotes.isEmpty {
                    ProgressView("拉取行情…")
                } else {
                    ForEach(market.quotes) { q in
                        HStack {
                            Image(systemName: q.systemImage)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.title).font(.subheadline.weight(.semibold))
                                Text(q.subtitle).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(q.value)
                                .font(.subheadline.monospacedDigit().weight(.medium))
                        }
                        .padding(.vertical, 2)
                    }
                }
            } footer: {
                if let t = market.updatedAt {
                    Text("更新于 \(t.formatted(date: .omitted, time: .standard)) · 安徽零售油价优先 · 数据仅供参考")
                } else {
                    Text("安徽油价 iamwawa · 汇率 Frankfurter · 原油 stooq · 金价尽力拉取")
                }
            }
        }
        .navigationTitle("行情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await market.refresh() }
                } label: {
                    if market.isLoading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .refreshable { await market.refresh() }
        .task { await market.refresh() }
    }
}

// MARK: - Express

struct ExpressHomeView: View {
    var prefill: String? = nil
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var store = ExpressService.shared
    @State private var number = ""
    @State private var note = ""
    @State private var phoneTail = ""

    var body: some View {
        List {
            Section {
                if store.hasAPICredentials {
                    Label("快递100 实时查询已就绪", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("未配置快递100密钥：请到设置 → 快递100 填写 customer 与授权 key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("快递单号", text: $number)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("手机后四位（顺丰建议填）", text: $phoneTail)
                    .keyboardType(.numberPad)
                TextField("备注（可选）", text: $note)
                Button("添加并查询") {
                    store.add(trackingNo: number, note: note, phoneTail: phoneTail)
                    if let id = store.packages.first?.id {
                        Task { await store.lookup(id) }
                    }
                    number = ""
                    note = ""
                    phoneTail = ""
                    Haptics.success()
                }
                .disabled(number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("协议对齐官网 Python/Java：param 紧凑 JSON + MD5(param+key+customer)。顺丰等可能需手机后四位。")
            }

            if let msg = store.lastLookupMessage {
                Section { Text(msg).font(.caption).foregroundStyle(.secondary) }
            }

            Section("包裹 (\(store.packages.count))") {
                if store.packages.isEmpty {
                    Text("暂无包裹").foregroundStyle(.secondary)
                } else {
                    ForEach(store.packages) { p in
                        NavigationLink {
                            ExpressDetailView(packageId: p.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(p.trackingNo).font(.subheadline.weight(.semibold).monospaced())
                                    Spacer()
                                    Text(p.carrierName).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(p.lastStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { idx in
                        idx.map { store.packages[$0].id }.forEach(store.delete)
                    }
                }
            }
        }
        .navigationTitle("快递")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let prefill, !prefill.isEmpty, number.isEmpty {
                number = ActionRouter.extractTrackingNumber(from: prefill) ?? prefill
            }
        }
    }
}

struct ExpressDetailView: View {
    let packageId: String
    @StateObject private var store = ExpressService.shared
    @State private var phoneDraft = ""

    private var package: ExpressRecord? {
        store.packages.first { $0.id == packageId }
    }

    var body: some View {
        List {
            if let p = package {
                Section("运单") {
                    LabeledContent("单号", value: p.trackingNo)
                    LabeledContent("承运商", value: "\(p.carrierName) (\(p.carrierCode))")
                    if let st = p.state {
                        LabeledContent("状态", value: ExpressService.stateLabel(st) ?? st)
                    }
                    if !p.note.isEmpty { LabeledContent("备注", value: p.note) }
                    TextField("手机后四位（顺丰等）", text: $phoneDraft)
                        .keyboardType(.numberPad)
                        .onAppear { phoneDraft = p.phoneTail }
                    Text(p.lastStatus).font(.subheadline)
                    if let t = p.updatedAt {
                        Text("更新于 \(t.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        store.updatePhoneTail(id: p.id, phoneTail: phoneDraft)
                        Task { await store.lookup(p.id) }
                    } label: {
                        if store.isQuerying {
                            ProgressView()
                        } else {
                            Label("实时查询", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isQuerying)
                    if let url = ExpressService.kuaidi100URL(trackingNo: p.trackingNo) {
                        Link("在快递100网页打开", destination: url)
                    }
                }
                Section("轨迹 (\(p.tracks.count))") {
                    if p.tracks.isEmpty {
                        Text("暂无轨迹，请点「实时查询」").foregroundStyle(.secondary)
                    } else {
                        ForEach(p.tracks) { ev in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(ev.time).font(.caption2).foregroundStyle(.secondary)
                                    if let s = ev.status, !s.isEmpty {
                                        Text(s).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                                    }
                                }
                                Text(ev.context).font(.subheadline)
                                if let loc = ev.location, !loc.isEmpty {
                                    Text(loc).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else {
                Text("包裹不存在")
            }
        }
        .navigationTitle("物流详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let p = package, p.tracks.isEmpty {
                await store.lookup(p.id)
            }
        }
    }
}

// MARK: - Password

struct PasswordGeneratorHomeView: View {
    @State private var options = PasswordGenerator.Options()
    @State private var password = PasswordGenerator.generate()
    @ObservedObject private var clipboard = ClipboardStore.shared

    var body: some View {
        Form {
            Section("结果") {
                Text(password)
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
                LabeledContent("强度", value: PasswordGenerator.strengthLabel(for: password))
                Button {
                    password = PasswordGenerator.generate(options)
                    Haptics.light()
                } label: { Label("重新生成", systemImage: "arrow.clockwise") }
                Button {
                    clipboard.copyToPasteboard(password)
                    clipboard.addManual(password)
                    Haptics.success()
                } label: { Label("复制并记入剪贴板历史", systemImage: "doc.on.doc") }
            }
            Section("选项") {
                Stepper("长度 \(options.length)", value: $options.length, in: 8...64)
                Toggle("大写", isOn: $options.uppercase)
                Toggle("小写", isOn: $options.lowercase)
                Toggle("数字", isOn: $options.digits)
                Toggle("符号", isOn: $options.symbols)
                Toggle("排除易混字符", isOn: $options.excludeAmbiguous)
            }
        }
        .navigationTitle("密码生成")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: options) { _, _ in
            password = PasswordGenerator.generate(options)
        }
    }
}
