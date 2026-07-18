import SwiftUI
import PhotosUI

/// Sheet: 生图 / 编辑 / 视频 (K16 secondary path).
struct ImagineComposeView: View {
    @ObservedObject var viewModel: ImagineViewModel
    /// Active conversation to attach results to; nil creates a new 「创作」 session.
    var conversationID: UUID?
    var onFinished: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("模式", selection: $viewModel.mode) {
                        ForEach(ImagineViewModel.Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .disabled(viewModel.isRunning)
                }

                Section {
                    TextField(promptPlaceholder, text: $viewModel.prompt, axis: .vertical)
                        .lineLimit(3...8)
                        .disabled(viewModel.isRunning)
                } header: {
                    Text("提示词")
                }

                if viewModel.mode == .edit {
                    Section {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            HStack {
                                Label(
                                    viewModel.selectedImageData == nil ? "选择图片" : "重新选择图片",
                                    systemImage: "photo.on.rectangle"
                                )
                                Spacer()
                                if viewModel.selectedImageData != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(viewModel.isRunning)

                        if let data = viewModel.selectedImageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    } header: {
                        Text("图源")
                    } footer: {
                        Text("从相册选择一张图片作为编辑输入。图片会在本地压缩后以 data URL 提交。")
                    }
                }

                Section {
                    modelPicker
                } header: {
                    Text("模型")
                } footer: {
                    Text("文本对话模型请在聊天页选择；此处仅 Imagine 媒体模型。")
                }

                if let note = viewModel.progressNote, viewModel.isRunning {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let err = viewModel.errorMessage {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                Section {
                    Button {
                        viewModel.generate(into: conversationID)
                    } label: {
                        PrimaryButtonLabel(
                            title: submitTitle,
                            systemImage: submitSymbol,
                            isBusy: viewModel.isRunning
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!viewModel.canSubmit)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)

                    if viewModel.isRunning {
                        Button(role: .destructive) {
                            viewModel.cancel()
                        } label: {
                            Text("取消")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .navigationTitle("创作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        if viewModel.isRunning {
                            viewModel.cancel()
                        }
                        dismiss()
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
            .onChange(of: viewModel.isRunning) { wasRunning, running in
                // Auto-dismiss after a successful run (error keeps sheet open).
                if wasRunning && !running, viewModel.errorMessage == nil {
                    onFinished?()
                    dismiss()
                }
            }
            .task {
                await viewModel.loadModels()
            }
        }
    }

    // MARK: - Model picker

    @ViewBuilder
    private var modelPicker: some View {
        switch viewModel.mode {
        case .image:
            Picker("生图模型", selection: $viewModel.imageModel) {
                ForEach(viewModel.availableImageModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .disabled(viewModel.isRunning)
        case .edit:
            Picker("编辑模型", selection: $viewModel.editModel) {
                ForEach(viewModel.availableEditModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .disabled(viewModel.isRunning)
        case .video:
            Picker("视频模型", selection: $viewModel.videoModel) {
                ForEach(viewModel.availableVideoModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .disabled(viewModel.isRunning)
        }
    }

    private var promptPlaceholder: String {
        switch viewModel.mode {
        case .image: return "描述你想生成的图片…"
        case .edit: return "描述如何编辑这张图…"
        case .video: return "描述你想生成的视频…"
        }
    }

    private var submitTitle: String {
        switch viewModel.mode {
        case .image: return "生成图片"
        case .edit: return "开始编辑"
        case .video: return "生成视频"
        }
    }

    private var submitSymbol: String {
        switch viewModel.mode {
        case .image: return "photo"
        case .edit: return "wand.and.stars"
        case .video: return "film"
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    viewModel.selectedImageData = data
                    viewModel.errorMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = "无法读取所选图片"
            }
        }
    }
}

#Preview {
    ImagineComposeView(viewModel: ImagineViewModel())
        .environmentObject(AppSettings.shared)
}
