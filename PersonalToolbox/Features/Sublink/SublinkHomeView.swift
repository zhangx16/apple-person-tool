import SwiftUI

struct SublinkHomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SublinkViewModel()

    @State private var showAddNode = false
    @State private var editingNode: SublinkNode?
    @State private var showBulkImport = false
    @State private var showAddSub = false
    @State private var editingSub: SublinkSub?
    @State private var clientSheetSub: SublinkSub?
    @State private var nodePendingDelete: SublinkNode?
    @State private var subPendingDelete: SublinkSub?

    var body: some View {
        Group {
            if viewModel.isLoggedIn {
                managedContent
            } else {
                ScrollView {
                    loginSection
                        .padding(16)
                }
            }
        }
        .background(AppSurfaceBackground(accent: Color.accentColor))
        .navigationTitle("SublinkX")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .sublink, title: "SublinkX")
            }
            if viewModel.isLoggedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddNode = true
                        } label: {
                            Label("新增节点", systemImage: "plus.circle")
                        }
                        Button {
                            showBulkImport = true
                        } label: {
                            Label("批量导入节点", systemImage: "square.and.arrow.down.on.square")
                        }
                        Button {
                            showAddSub = true
                        } label: {
                            Label("新建订阅", systemImage: "link.badge.plus")
                        }
                        Divider()
                        Button(role: .destructive) {
                            viewModel.logout()
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .refreshable {
            if viewModel.isLoggedIn {
                await viewModel.refresh(settings: settings)
            } else {
                await viewModel.refreshCaptcha(settings: settings)
            }
        }
        .task {
            await viewModel.bootstrap(settings: settings)
        }
        .overlay(alignment: .bottom) {
            bannerStack
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .sheet(isPresented: $showAddNode) {
            NodeEditorSheet(
                title: "新增节点",
                initialName: "",
                initialLink: "",
                initialGroup: "",
                knownGroups: viewModel.groups,
                isBusy: viewModel.isMutating
            ) { name, link, group in
                let ok = await viewModel.addNode(
                    settings: settings,
                    name: name,
                    link: link,
                    group: group
                )
                if ok { showAddNode = false }
                return ok
            }
        }
        .sheet(item: $editingNode) { node in
            NodeEditorSheet(
                title: "编辑节点",
                initialName: node.name ?? "",
                initialLink: node.link ?? "",
                initialGroup: node.groupCSV,
                knownGroups: viewModel.groups,
                isBusy: viewModel.isMutating
            ) { name, link, group in
                guard let id = node.nodeId else {
                    viewModel.errorMessage = "节点缺少 ID"
                    return false
                }
                let ok = await viewModel.updateNode(
                    settings: settings,
                    id: id,
                    name: name,
                    link: link,
                    group: group
                )
                if ok { editingNode = nil }
                return ok
            }
        }
        .sheet(isPresented: $showBulkImport) {
            BulkImportSheet(
                knownGroups: viewModel.groups,
                isBusy: viewModel.isMutating
            ) { text, group in
                let ok = await viewModel.bulkImportNodes(
                    settings: settings,
                    rawText: text,
                    group: group
                )
                if ok { showBulkImport = false }
                return ok
            }
        }
        .sheet(isPresented: $showAddSub) {
            SubEditorSheet(
                title: "新建订阅",
                initialName: "",
                initialConfig: .default,
                initialSelected: [],
                allNodes: viewModel.nodes,
                isBusy: viewModel.isMutating
            ) { name, selected, config in
                let ok = await viewModel.addSubscription(
                    settings: settings,
                    name: name,
                    nodeNames: selected,
                    config: config
                )
                if ok { showAddSub = false }
                return ok
            }
        }
        .sheet(item: $editingSub) { sub in
            SubEditorSheet(
                title: "编辑订阅",
                initialName: sub.name ?? "",
                initialConfig: sub.parsedConfig,
                initialSelected: sub.nodeNames,
                allNodes: viewModel.nodes,
                isBusy: viewModel.isMutating
            ) { name, selected, config in
                let ok = await viewModel.updateSubscription(
                    settings: settings,
                    oldName: sub.name ?? "",
                    name: name,
                    nodeNames: selected,
                    config: config
                )
                if ok { editingSub = nil }
                return ok
            }
        }
        .sheet(item: $clientSheetSub) { sub in
            ClientLinksSheet(
                subscriptionName: sub.displayName,
                baseURL: settings.sublinkBaseURL
            ) { url, label in
                viewModel.copyToPasteboard(url, label: label)
            }
        }
        .confirmationDialog(
            "删除节点？",
            isPresented: Binding(
                get: { nodePendingDelete != nil },
                set: { if !$0 { nodePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let node = nodePendingDelete {
                Button("删除 \(node.displayName)", role: .destructive) {
                    Task {
                        _ = await viewModel.deleteNode(settings: settings, node: node)
                        nodePendingDelete = nil
                    }
                }
            }
            Button("取消", role: .cancel) { nodePendingDelete = nil }
        } message: {
            Text("此操作不可撤销。若订阅仍引用该节点名，需另行编辑订阅。")
        }
        .confirmationDialog(
            "删除订阅？",
            isPresented: Binding(
                get: { subPendingDelete != nil },
                set: { if !$0 { subPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let sub = subPendingDelete {
                Button("删除 \(sub.displayName)", role: .destructive) {
                    Task {
                        _ = await viewModel.deleteSubscription(settings: settings, sub: sub)
                        subPendingDelete = nil
                    }
                }
            }
            Button("取消", role: .cancel) { subPendingDelete = nil }
        } message: {
            Text("删除后客户端链接将失效。")
        }
    }

    // MARK: - Managed content

    private var managedContent: some View {
        VStack(spacing: 0) {
            Picker("分区", selection: $viewModel.pane) {
                ForEach(SublinkViewModel.Pane.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if viewModel.isLoading && viewModel.nodes.isEmpty && viewModel.subscriptions.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewModel.pane {
                case .overview:
                    ScrollView {
                        overviewSection
                            .padding(16)
                    }
                case .nodes:
                    nodesList
                case .subscriptions:
                    subscriptionsList
                }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            let d = viewModel.dashboard
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("订阅", "\(d?.subscriptions ?? 0)", "link")
                metric("节点", "\(d?.nodes ?? 0)", "point.3.connected.trianglepath.dotted")
                metric("分组", "\(d?.groups ?? 0)", "folder")
                metric("访问量", "\(d?.accessCount ?? 0)", "chart.bar")
            }

            if let protocols = d?.protocols, !protocols.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("协议分布").font(.headline)
                    ForEach(protocols) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                            Text("\(p.count)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
            }

            if let recent = d?.recentAccess, !recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近访问").font(.headline)
                    ForEach(recent.prefix(10)) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.subscription).font(.subheadline.weight(.medium))
                            Text("\(r.address) · \(r.date) · \(r.count) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
            }

            HStack(spacing: 12) {
                Button {
                    showAddNode = true
                } label: {
                    Label("加节点", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showAddSub = true
                } label: {
                    Label("建订阅", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Text(settings.sublinkBaseURL)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Nodes list

    private var nodesList: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索名称 / 链接 / 分组", text: $viewModel.nodeSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if !viewModel.groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            groupChip("全部", selected: viewModel.selectedGroupFilter == nil) {
                                viewModel.selectedGroupFilter = nil
                            }
                            ForEach(viewModel.groups, id: \.self) { g in
                                groupChip(g, selected: viewModel.selectedGroupFilter == g) {
                                    viewModel.selectedGroupFilter = g
                                }
                            }
                        }
                    }
                }
            }

            Section {
                if viewModel.filteredNodes.isEmpty {
                    Text(viewModel.nodes.isEmpty ? "暂无节点，点右上角添加" : "无匹配节点")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.filteredNodes) { node in
                        nodeRow(node)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    nodePendingDelete = node
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editingNode = node
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if let link = node.link, !link.isEmpty {
                                    Button {
                                        viewModel.copyToPasteboard(link, label: "已复制节点链接")
                                    } label: {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                }
            } header: {
                Text("节点 \(viewModel.filteredNodes.count)/\(viewModel.nodes.count)")
            } footer: {
                Text("左滑删除/编辑，右滑复制链接。也可用右上角菜单批量导入。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func nodeRow(_ node: SublinkNode) -> some View {
        Button {
            editingNode = node
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(node.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if node.nodeId != nil {
                        Text("#\(node.nodeId!)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let link = node.link, !link.isEmpty {
                    Text(link)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !node.groupNames.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(node.groupNames, id: \.self) { g in
                            Text(g)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func groupChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscriptions list

    private var subscriptionsList: some View {
        List {
            Section {
                if viewModel.subscriptions.isEmpty {
                    Text("暂无订阅，点右上角或概览页创建")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.subscriptions) { sub in
                        subRow(sub)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    subPendingDelete = sub
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editingSub = sub
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    let url = viewModel.clientURL(
                                        settings: settings,
                                        subscriptionName: sub.name ?? "",
                                        client: .auto
                                    )
                                    viewModel.copyToPasteboard(url, label: "已复制订阅链接")
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                    }
                }
            } header: {
                Text("订阅 \(viewModel.subscriptions.count)")
            } footer: {
                Text("左滑删除/编辑，右滑复制自动识别订阅 URL。点「客户端」可复制 Clash/V2Ray/Surge 专用链接。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func subRow(_ sub: SublinkSub) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sub.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if sub.subId != nil {
                    Text("#\(sub.subId!)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text("节点 \(sub.nodeNames.count) 个")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !sub.nodeNames.isEmpty {
                Text(sub.nodeNames.prefix(6).joined(separator: " · ")
                     + (sub.nodeNames.count > 6 ? " …" : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button {
                    clientSheetSub = sub
                } label: {
                    Label("客户端", systemImage: "qrcode")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button {
                    editingSub = sub
                } label: {
                    Label("编辑", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button {
                    let url = viewModel.clientURL(
                        settings: settings,
                        subscriptionName: sub.name ?? "",
                        client: .auto
                    )
                    viewModel.copyToPasteboard(url, label: "已复制订阅链接")
                } label: {
                    Label("复制链接", systemImage: "link")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Login

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录 SublinkX")
                .font(.headline)
            Text(settings.sublinkBaseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("用户 \(settings.sublinkUsername)")
                .font(.subheadline)

            if let img = viewModel.captchaImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        Task { await viewModel.refreshCaptcha(settings: settings) }
                    }
                    .accessibilityLabel("验证码图片，点按刷新")
            }

            HStack {
                TextField("验证码", text: $viewModel.captchaCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("刷新") {
                    Task { await viewModel.refreshCaptcha(settings: settings) }
                }
            }

            Button {
                Task { await viewModel.login(settings: settings) }
            } label: {
                PrimaryButtonLabel(title: "登录", systemImage: "person.badge.key", isBusy: viewModel.isLoading)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(viewModel.captchaCode.isEmpty || viewModel.isLoading)

            Text("账号密码请在「设置 → SublinkX」中配置。登录后可新增/删除节点与订阅。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
    }

    // MARK: - Banners

    @ViewBuilder
    private var bannerStack: some View {
        VStack(spacing: 8) {
            if let err = viewModel.errorMessage {
                banner(text: err, isError: true) {
                    viewModel.errorMessage = nil
                }
            }
            if let status = viewModel.statusMessage {
                banner(text: status, isError: false) {
                    viewModel.statusMessage = nil
                }
                .task(id: status) {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if viewModel.statusMessage == status {
                        viewModel.statusMessage = nil
                    }
                }
            }
        }
    }

    private func banner(text: String, isError: Bool, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isError ? Color.red : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            (isError ? Color.red.opacity(0.12) : Color.green.opacity(0.14)),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Node editor

private struct NodeEditorSheet: View {
    let title: String
    let initialName: String
    let initialLink: String
    let initialGroup: String
    let knownGroups: [String]
    let isBusy: Bool
    let onSave: (String, String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var link: String = ""
    @State private var group: String = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("节点") {
                    TextField("名称（可空，后端可从链接解析）", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("分享链接（含协议头）", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...8)
                }
                Section("分组") {
                    TextField("分组，逗号分隔", text: $group)
                        .textInputAutocapitalization(.never)
                    if !knownGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(knownGroups, id: \.self) { g in
                                    Button(g) {
                                        toggleGroup(g)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                if let localError {
                    Section {
                        Text(localError).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBusy {
                        ProgressView()
                    } else {
                        Button("保存") {
                            Task {
                                localError = nil
                                let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard trimmed.contains("://") else {
                                    localError = "链接需包含协议头，如 vless://、ss://"
                                    return
                                }
                                _ = await onSave(name, trimmed, group)
                            }
                        }
                    }
                }
            }
            .onAppear {
                name = initialName
                link = initialLink
                group = initialGroup
            }
            .disabled(isBusy)
        }
    }

    private func toggleGroup(_ g: String) {
        var parts = group
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let idx = parts.firstIndex(of: g) {
            parts.remove(at: idx)
        } else {
            parts.append(g)
        }
        group = parts.joined(separator: ",")
    }
}

// MARK: - Bulk import

private struct BulkImportSheet: View {
    let knownGroups: [String]
    let isBusy: Bool
    let onImport: (String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var group = ""
    @State private var localError: String?

    private var linkCount: Int {
        text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("节点链接（每行一个，最多 500）")
                } footer: {
                    Text("已识别 \(linkCount) 条")
                }
                Section("可选分组") {
                    TextField("分组，逗号分隔", text: $group)
                    if !knownGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(knownGroups, id: \.self) { g in
                                    Button(g) {
                                        if group.isEmpty { group = g }
                                        else if !group.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains(g) {
                                            group += ",\(g)"
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                if let localError {
                    Section { Text(localError).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBusy {
                        ProgressView()
                    } else {
                        Button("导入") {
                            Task {
                                localError = nil
                                guard linkCount > 0 else {
                                    localError = "请粘贴节点链接"
                                    return
                                }
                                _ = await onImport(text, group)
                            }
                        }
                    }
                }
            }
            .disabled(isBusy)
        }
    }
}

// MARK: - Sub editor

private struct SubEditorSheet: View {
    let title: String
    let initialName: String
    let initialConfig: SublinkSubConfig
    let initialSelected: [String]
    let allNodes: [SublinkNode]
    let isBusy: Bool
    let onSave: (String, [String], SublinkSubConfig) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<String> = []
    @State private var ordered: [String] = []
    @State private var clash = SublinkSubConfig.default.clash
    @State private var surge = SublinkSubConfig.default.surge
    @State private var udp = false
    @State private var cert = false
    @State private var nodeFilter = ""
    @State private var localError: String?

    private var filteredAll: [SublinkNode] {
        let q = nodeFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allNodes }
        return allNodes.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(q)
                || ($0.link ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅") {
                    TextField("名称", text: $name)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Toggle("强制 UDP", isOn: $udp)
                    Toggle("跳过证书验证", isOn: $cert)
                    TextField("Clash 模板路径/URL", text: $clash)
                        .textInputAutocapitalization(.never)
                        .font(.footnote)
                    TextField("Surge 模板路径/URL", text: $surge)
                        .textInputAutocapitalization(.never)
                        .font(.footnote)
                } header: {
                    Text("配置")
                } footer: {
                    Text("默认模板与 Web 后台一致：./template/clash.yaml 与 ./template/surge.conf")
                }

                Section {
                    TextField("筛选节点", text: $nodeFilter)
                        .textInputAutocapitalization(.never)
                    if ordered.isEmpty {
                        Text("尚未选择节点")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(ordered.enumerated()), id: \.element) { index, n in
                            HStack(spacing: 10) {
                                VStack(spacing: 2) {
                                    Button {
                                        moveNode(at: index, by: -1)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                    }
                                    .disabled(index == 0)
                                    Button {
                                        moveNode(at: index, by: 1)
                                    } label: {
                                        Image(systemName: "chevron.down")
                                    }
                                    .disabled(index == ordered.count - 1)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)

                                Text("\(index + 1). \(n)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button(role: .destructive) {
                                    removeNode(n)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("已选节点（\(ordered.count)）")
                } footer: {
                    Text("上下箭头调整顺序，顺序会写入 NodeOrder。")
                }

                Section("可选节点") {
                    if filteredAll.isEmpty {
                        Text("没有可添加的节点")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredAll) { node in
                            let n = node.name ?? ""
                            if !n.isEmpty {
                                Button {
                                    toggleNode(n)
                                } label: {
                                    HStack {
                                        Image(systemName: selected.contains(n) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(n) ? Color.accentColor : Color.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(n).foregroundStyle(.primary)
                                            if let link = node.link {
                                                Text(link)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let localError {
                    Section {
                        Text(localError).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBusy {
                        ProgressView()
                    } else {
                        Button("保存") {
                            Task {
                                localError = nil
                                let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !n.isEmpty else {
                                    localError = "订阅名称不能为空"
                                    return
                                }
                                guard !ordered.isEmpty else {
                                    localError = "请至少选择一个节点"
                                    return
                                }
                                let config = SublinkSubConfig(
                                    clash: clash.trimmingCharacters(in: .whitespacesAndNewlines),
                                    surge: surge.trimmingCharacters(in: .whitespacesAndNewlines),
                                    udp: udp,
                                    cert: cert
                                )
                                _ = await onSave(n, ordered, config)
                            }
                        }
                    }
                }
            }
            .onAppear {
                name = initialName
                clash = initialConfig.clash
                surge = initialConfig.surge
                udp = initialConfig.udp
                cert = initialConfig.cert
                ordered = initialSelected
                selected = Set(initialSelected)
            }
            .disabled(isBusy)
        }
    }

    private func toggleNode(_ n: String) {
        if selected.contains(n) {
            removeNode(n)
        } else {
            selected.insert(n)
            ordered.append(n)
        }
    }

    private func removeNode(_ n: String) {
        selected.remove(n)
        ordered.removeAll { $0 == n }
    }

    private func moveNode(at index: Int, by delta: Int) {
        let target = index + delta
        guard ordered.indices.contains(index), ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
    }
}

// MARK: - Client links

private struct ClientLinksSheet: View {
    let subscriptionName: String
    let baseURL: String
    let onCopy: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(subscriptionName)
                        .font(.headline)
                    Text(baseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(SublinkClientKind.allCases) { kind in
                        clientLinkRow(kind: kind)
                    }
                } header: {
                    Text("订阅链接")
                } footer: {
                    Text("token 为订阅名的 MD5，与 Web 后台一致。")
                }
            }
            .navigationTitle("客户端链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func clientLinkRow(kind: SublinkClientKind) -> some View {
        let url = SublinkURLBuilder.clientURL(
            baseURL: baseURL,
            subscriptionName: subscriptionName,
            client: kind
        )
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.title)
                .font(.subheadline.weight(.semibold))
            Text(url)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("复制") {
                    onCopy(url, "已复制 \(kind.title) 链接")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                if let shareURL = URL(string: url) {
                    ShareLink(item: shareURL) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
