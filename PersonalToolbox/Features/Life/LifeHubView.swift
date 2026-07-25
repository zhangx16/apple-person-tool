import SwiftUI
import UIKit

/// Unified life hub: reminders · subscriptions · anniversary · habits · notes.
struct LifeHubView: View {
    var body: some View {
        List {
            Section {
                Text("把常用生活工具收在一处：到期提醒、账单、纪念日、习惯待办与 Markdown 笔记。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("时间与账单") {
                NavigationLink {
                    ReminderHomeView()
                } label: {
                    Label("提醒倒计时", systemImage: "bell.badge")
                }
                NavigationLink {
                    SubscriptionHomeView()
                } label: {
                    Label("订阅账单", systemImage: "creditcard")
                }
                NavigationLink {
                    AnniversaryHomeView()
                } label: {
                    Label("纪念日", systemImage: "heart.text.square")
                }
            }
            Section("习惯与笔记") {
                NavigationLink {
                    HabitsTodosHomeView()
                } label: {
                    Label("习惯与待办", systemImage: "checklist")
                }
                NavigationLink {
                    FastNoteHomeView()
                } label: {
                    Label("笔记同步 (Markdown)", systemImage: "doc.richtext")
                }
                NavigationLink {
                    LocalMarkdownScratchView()
                } label: {
                    Label("本地 Markdown 草稿", systemImage: "text.alignleft")
                }
            }
        }
        .navigationTitle("生活中心")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lightweight local markdown note (preview + edit), no cloud.
struct LocalMarkdownScratchView: View {
    @State private var text: String = UserDefaults.standard.string(forKey: "life.markdown.scratch") ?? """
    # 草稿

    支持 **粗体**、`行内代码` 与代码块：

    ```
    print("hello")
    ```

    - 列表项
    - 另一项
    """
    @State private var preview = true

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $preview) {
                Text("编辑").tag(false)
                Text("预览").tag(true)
            }
            .pickerStyle(.segmented)
            .padding()

            if preview {
                ScrollView {
                    MarkdownLiteView(text: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .padding(.horizontal, 8)
            }
        }
        .navigationTitle("Markdown 草稿")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: text) { _, v in
            UserDefaults.standard.set(v, forKey: "life.markdown.scratch")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("复制") {
                    UIPasteboard.general.string = text
                    Haptics.success()
                }
            }
        }
    }
}

/// Minimal Markdown renderer for notes (headers, bold, code, lists). No HTML.
struct MarkdownLiteView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let t):
                    Text(t)
                        .font(level <= 1 ? .title2.bold() : (level == 2 ? .title3.bold() : .headline))
                        .padding(.top, 4)
                case .code(let code):
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .listItem(let t):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(inline(t))
                    }
                case .paragraph(let t):
                    Text(inline(t))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private enum Block {
        case heading(Int, String)
        case code(String)
        case listItem(String)
        case paragraph(String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                i += 1
                var code: [String] = []
                while i < lines.count, !lines[i].hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }
            if line.hasPrefix("### ") {
                blocks.append(.heading(3, String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(2, String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                blocks.append(.heading(1, String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.listItem(String(line.dropFirst(2))))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // skip blank
            } else {
                blocks.append(.paragraph(line))
            }
            i += 1
        }
        return blocks
    }

    private func inline(_ s: String) -> AttributedString {
        var result = AttributedString(s)
        // `code`
        if let re = try? NSRegularExpression(pattern: "`([^`]+)`") {
            let ns = s as NSString
            let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                guard m.numberOfRanges > 1,
                      let full = Range(m.range(at: 0), in: s),
                      let inner = Range(m.range(at: 1), in: s),
                      let attrRange = result.range(of: String(s[full])) else { continue }
                var code = AttributedString(String(s[inner]))
                code.font = .body.monospaced()
                code.backgroundColor = Color(.tertiarySystemFill)
                result.replaceSubrange(attrRange, with: code)
            }
        }
        // **bold**
        if let re = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#) {
            let ns = String(result.characters) as NSString
            let str = String(result.characters)
            let matches = re.matches(in: str, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                guard m.numberOfRanges > 1,
                      let full = Range(m.range(at: 0), in: str),
                      let inner = Range(m.range(at: 1), in: str),
                      let attrRange = result.range(of: String(str[full])) else { continue }
                var bold = AttributedString(String(str[inner]))
                bold.font = .body.bold()
                result.replaceSubrange(attrRange, with: bold)
            }
        }
        return result
    }
}
