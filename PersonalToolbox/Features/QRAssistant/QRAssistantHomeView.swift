import SwiftUI
import PhotosUI
import Photos

/// 二维码助手：扫码 / 生成 / 历史（参考 iamwaa/Scripting「二维码助手」）。
struct QRAssistantHomeView: View {
    @ObservedObject private var store = QRAssistantStore.shared
    @State private var segment: Segment = .scan
    @State private var scanMode: QRScanMode = .single
    @State private var showCamera = false
    @State private var showRules = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var toast: String?
    @State private var generateText = ""
    @State private var generatedImage: UIImage?
    @State private var selectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showClearConfirm = false

    private enum Segment: String, CaseIterable, Identifiable {
        case scan = "扫码"
        case generate = "生成"
        case history = "历史"
        var id: String { rawValue }
    }

    private let accent = QRRedirectDefaults.accent

    var body: some View {
        VStack(spacing: 0) {
            Picker("分段", selection: $segment) {
                ForEach(Segment.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch segment {
                case .scan: scanPane
                case .generate: generatePane
                case .history: historyPane
                }
            }
        }
        .background(AppSurfaceBackground(accent: Color.accentColor))
        .navigationTitle("二维码助手")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServiceBrandTitle(brand: .qrAssistant, title: "二维码助手")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if segment == .history {
                    Button(selectionMode ? "完成" : "选择") {
                        selectionMode.toggle()
                        if !selectionMode { selectedIds.removeAll() }
                    }
                } else if segment == .scan {
                    Button {
                        showRules = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("跳转规则与设置")
                }
            }
        }
        .onAppear {
            if !store.isLoaded { store.load() }
            if store.settings.autoScanOnOpen, segment == .scan {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showCamera = true
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            QRScannerSheet(scanMode: $scanMode) { content in
                handleScanned(content)
            }
        }
        .sheet(isPresented: $showRules) {
            NavigationStack {
                QRRedirectConfigView(store: store)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await recognizePhoto(item) }
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
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AppleTheme.preferredSnappy, value: toast)
    }

    // MARK: - Scan

    private var scanPane: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("模式")
                        .font(.subheadline.weight(.semibold))
                    Picker("模式", selection: $scanMode) {
                        ForEach(QRScanMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("启动时自动打开扫码", isOn: Binding(
                        get: { store.settings.autoScanOnOpen },
                        set: { store.setAutoScanOnOpen($0) }
                    ))
                    Toggle("识别后智能跳转", isOn: Binding(
                        get: { store.settings.autoRedirect },
                        set: { store.setAutoRedirect($0) }
                    ))
                    if store.settings.autoRedirect {
                        Text("按关键字匹配规则，打开微信 / 支付宝等 App 扫码入口")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("配置")
            }

            Section {
                Button {
                    showCamera = true
                } label: {
                    Label("打开相机扫码", systemImage: "camera.viewfinder")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(accent)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(
                        isRecognizing ? "识别中…" : "相册识别",
                        systemImage: "photo.on.rectangle"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isRecognizing)

                Button {
                    showRules = true
                } label: {
                    Label("跳转规则（\(store.settings.redirectRules.count)）", systemImage: "arrow.triangle.branch")
                }
            } header: {
                Text("操作")
            }

            if let recent = store.records.first {
                Section("最近一条") {
                    QRRecordRow(record: recent) {
                        openRecord(recent)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Generate

    private var generatePane: some View {
        List {
            Section("内容") {
                TextField("输入文本或链接", text: $generateText, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("生成二维码") {
                    generate()
                }
                .disabled(generateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .fontWeight(.semibold)
                .tint(accent)
            }

            if let generatedImage {
                Section("预览") {
                    HStack {
                        Spacer()
                        Image(uiImage: generatedImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 240)
                            .padding(8)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    Button {
                        shareImage(generatedImage)
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        saveToPhotos(generatedImage)
                    } label: {
                        Label("保存到相册", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        UIPasteboard.general.string = generateText
                        flashToast("已复制内容")
                        Haptics.success()
                    } label: {
                        Label("复制原文", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - History

    private var historyPane: some View {
        Group {
            if store.records.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(accent.opacity(0.85))
                    Text("暂无历史")
                        .font(.title3.weight(.semibold))
                    Text("扫码或生成后会出现在这里")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.records) { record in
                        HStack(spacing: 10) {
                            if selectionMode {
                                Image(systemName: selectedIds.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIds.contains(record.id) ? accent : Color.secondary)
                            }
                            QRRecordRow(record: record) {
                                if selectionMode {
                                    if selectedIds.contains(record.id) {
                                        selectedIds.remove(record.id)
                                    } else {
                                        selectedIds.insert(record.id)
                                    }
                                } else {
                                    openRecord(record)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.deleteRecord(id: record.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = record.content
                                flashToast("已复制")
                                Haptics.success()
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                            Button {
                                openRecord(record)
                            } label: {
                                Label("打开", systemImage: "safari")
                            }
                            Button {
                                generateText = record.content
                                segment = .generate
                                generate()
                            } label: {
                                Label("重新生成", systemImage: "qrcode")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { store.records[$0].id }
                        store.deleteRecords(ids: Set(ids))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    if selectionMode, !selectedIds.isEmpty {
                        HStack {
                            Button(role: .destructive) {
                                store.deleteRecords(ids: selectedIds)
                                selectedIds.removeAll()
                            } label: {
                                Label("删除 \(selectedIds.count) 项", systemImage: "trash")
                            }
                            Spacer()
                        }
                        .padding()
                        .background(.bar)
                    } else if !selectionMode {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Text("清空历史")
                                .frame(maxWidth: .infinity)
                        }
                        .padding()
                    }
                }
                .confirmationDialog("清空全部历史记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                    Button("清空", role: .destructive) { store.clearRecords() }
                    Button("取消", role: .cancel) {}
                }
            }
        }
    }

    // MARK: - Actions

    private func handleScanned(_ content: String) {
        store.addRecord(content: content, type: .scan)
        flashToast("识别成功")
        _ = store.tryRedirect(content: content)
        if scanMode == .single {
            showCamera = false
        }
    }

    private func recognizePhoto(_ item: PhotosPickerItem) async {
        isRecognizing = true
        defer { isRecognizing = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            flashToast("无法读取图片")
            return
        }
        if let text = await QRCodeToolkit.parseQR(from: image) {
            store.addRecord(content: text, type: .scan)
            flashToast("识别成功")
            _ = store.tryRedirect(content: text)
        } else {
            flashToast("未识别到二维码")
            Haptics.error()
        }
    }

    private func generate() {
        let text = generateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let img = QRCodeToolkit.generateImage(from: text) {
            generatedImage = img
            store.addRecord(content: text, type: .generate)
            flashToast("已生成")
        } else {
            flashToast("生成失败")
            Haptics.error()
        }
    }

    private func openRecord(_ record: QRRecord) {
        store.openContent(record.content)
    }

    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    flashToast("无相册写入权限")
                    return
                }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                flashToast("已保存到相册")
                Haptics.success()
            }
        }
    }

    private func shareImage(_ image: UIImage) {
        let ac = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = (scene.windows.first { $0.isKeyWindow } ?? scene.windows.first)?.rootViewController else {
            return
        }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        if let pop = ac.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        }
        presenter.present(ac, animated: true)
    }

    private func flashToast(_ message: String) {
        withAnimation {
            toast = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation {
                if toast == message { toast = nil }
            }
        }
    }
}

// MARK: - Row

struct QRRecordRow: View {
    let record: QRRecord
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: record.type.systemImage)
                    .font(.title3)
                    .foregroundStyle(QRRedirectDefaults.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.content)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(record.type.label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(QRRedirectDefaults.accent.opacity(0.14), in: Capsule())
                            .foregroundStyle(QRRedirectDefaults.accent)
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
