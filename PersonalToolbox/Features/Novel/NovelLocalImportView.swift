import SwiftUI
import UniformTypeIdentifiers

struct NovelLocalImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NovelShelfStore.self) private var shelf

    var onImported: (NovelBook) -> Void

    @State private var title = ""
    @State private var author = ""
    @State private var text = ""
    @State private var fileName = "novel.txt"
    @State private var showImporter = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("书籍信息") {
                    TextField("书名（可选，默认文件名）", text: $title)
                    TextField("作者（可选）", text: $author)
                }
                Section("正文") {
                    Button("从文件选择 TXT") { showImporter = true }
                    Button("从剪贴板粘贴") {
                        if let s = UIPasteboard.general.string {
                            text = s
                            if title.isEmpty { title = "剪贴板导入" }
                        }
                    }
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .font(.system(.caption, design: .monospaced))
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("导入本地 TXT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { importNow() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.plainText, .utf8PlainText, .text],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        if let s = String(data: data, encoding: .utf8)
                            ?? String(data: data, encoding: .isoLatin1) {
                            text = s
                            fileName = url.lastPathComponent
                            if title.isEmpty {
                                title = (fileName as NSString).deletingPathExtension
                            }
                        } else {
                            error = "无法解码文件"
                        }
                    } catch {
                        self.error = error.localizedDescription
                    }
                case .failure(let err):
                    error = err.localizedDescription
                }
            }
        }
    }

    private func importNow() {
        do {
            let book = try shelf.importLocalTXT(
                fileName: fileName,
                content: text,
                title: title.nilIfEmpty,
                author: author.nilIfEmpty
            )
            onImported(book)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
