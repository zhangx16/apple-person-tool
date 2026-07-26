import SwiftUI

/// Lightweight block-level Markdown parser for FastNote previews.
/// Handles fenced code blocks, headings, block quotes, lists and dividers.
/// Inline emphasis/links inside a block are left to `AttributedString(markdown:)`.
enum NoteMarkdown {
    enum Block {
        case heading(level: Int, text: String)
        case codeBlock(language: String, code: String)
        case blockquote(text: String)
        case listItem(text: String, ordered: Bool, index: Int)
        case divider
        case paragraph(text: String)
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text: text)) }
            paragraphLines = []
        }

        while i < lines.count {
            let rawLine = lines[i]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Fenced code block: ``` or ~~~, optionally followed by a language tag.
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(line.prefix(3))
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // consume closing fence, if any
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Heading: 1-6 `#` followed by a space.
            if line.hasPrefix("#") {
                let hashCount = line.prefix(while: { $0 == "#" }).count
                let afterHash = line.index(line.startIndex, offsetBy: hashCount)
                if hashCount >= 1, hashCount <= 6, afterHash < line.endIndex, line[afterHash] == " " {
                    flushParagraph()
                    let text = String(line.dropFirst(hashCount)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: hashCount, text: text))
                    i += 1
                    continue
                }
            }

            // Divider.
            if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                blocks.append(.divider)
                i += 1
                continue
            }

            // Blockquote.
            if line.hasPrefix(">") {
                flushParagraph()
                let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.blockquote(text: text))
                i += 1
                continue
            }

            // Unordered list.
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.listItem(text: text, ordered: false, index: 0))
                i += 1
                continue
            }

            // Ordered list: "1. text".
            if let dotRange = line.range(of: ". "),
               let num = Int(line[line.startIndex..<dotRange.lowerBound]) {
                flushParagraph()
                let text = String(line[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                blocks.append(.listItem(text: text, ordered: true, index: num))
                i += 1
                continue
            }

            if line.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraphLines.append(rawLine)
            i += 1
        }
        flushParagraph()
        return blocks
    }
}

/// Renders parsed Markdown blocks. Inline emphasis/links use the system
/// `AttributedString(markdown:)` parser; code blocks get a monospaced,
/// horizontally scrollable container so long lines don't wrap awkwardly.
struct NoteMarkdownView: View {
    let markdown: String

    private var blocks: [NoteMarkdown.Block] {
        NoteMarkdown.parse(markdown)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: NoteMarkdown.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level <= 2 ? 6 : 2)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                inlineText(text)
                    .foregroundStyle(.secondary)
            }
        case .listItem(let text, let ordered, let index):
            HStack(alignment: .top, spacing: 6) {
                Text(ordered ? "\(index)." : "•")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: ordered ? 20 : 12, alignment: .trailing)
                inlineText(text)
            }
        case .divider:
            Divider()
        case .paragraph(let text):
            inlineText(text)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    private func inlineText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}
