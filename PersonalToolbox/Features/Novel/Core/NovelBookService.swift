import Foundation

/// Search / TOC / content using Legado rules (native subset).
@MainActor
enum NovelBookService {

    static func search(
        key: String,
        sources: [BookSource],
        page: Int = 1,
        maxSources: Int = 12
    ) async -> (hits: [NovelSearchHit], errors: [String]) {
        let keyword = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return ([], []) }

        var hits: [NovelSearchHit] = []
        var errors: [String] = []
        let list = Array(sources.prefix(maxSources))

        await withTaskGroup(of: Result<[NovelSearchHit], Error>.self) { group in
            for source in list {
                group.addTask {
                    do {
                        let found = try await searchOne(source: source, key: keyword, page: page)
                        return .success(found)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let found):
                    hits.append(contentsOf: found)
                case .failure(let error):
                    errors.append(error.localizedDescription)
                }
            }
        }

        // Dedupe by name+author
        var seen = Set<String>()
        var unique: [NovelSearchHit] = []
        for h in hits {
            let k = "\(h.name)|\(h.author)".lowercased()
            if seen.insert(k).inserted { unique.append(h) }
        }
        return (unique, errors)
    }

    static func searchOne(source: BookSource, key: String, page: Int) async throws -> [NovelSearchHit] {
        guard source.supportsNativeEngine else {
            throw NovelError.ruleUnsupported("「\(source.bookSourceName)」含 JS 规则，当前引擎暂不执行")
        }
        guard let rule = source.ruleSearch, let listRule = rule.bookList, !listRule.isEmpty else {
            throw NovelError.ruleUnsupported("「\(source.bookSourceName)」缺少搜索列表规则")
        }
        let spec = try NovelNetworkClient.buildSearchRequest(source: source, key: key, page: page)
        let html = try await NovelNetworkClient.fetch(spec)
        let base = URL(string: source.bookSourceUrl)
        let fragments = LegadoRuleEngine.getList(rule: listRule, in: html)
        return fragments.compactMap { frag -> NovelSearchHit? in
            let name = LegadoRuleEngine.getString(rule: rule.name, in: frag, baseURL: base)
            guard !name.isEmpty else { return nil }
            let bookURL = LegadoRuleEngine.getString(rule: rule.bookUrl, in: frag, baseURL: base)
            guard !bookURL.isEmpty else { return nil }
            return NovelSearchHit(
                name: name,
                author: LegadoRuleEngine.getString(rule: rule.author, in: frag, baseURL: base),
                coverURL: LegadoRuleEngine.getString(rule: rule.coverUrl, in: frag, baseURL: base).nilIfEmpty,
                intro: LegadoRuleEngine.getString(rule: rule.intro, in: frag, baseURL: base).nilIfEmpty,
                kind: LegadoRuleEngine.getString(rule: rule.kind, in: frag, baseURL: base).nilIfEmpty,
                lastChapter: LegadoRuleEngine.getString(rule: rule.lastChapter, in: frag, baseURL: base).nilIfEmpty,
                bookURL: bookURL,
                sourceURL: source.bookSourceUrl,
                sourceName: source.bookSourceName
            )
        }
    }

    static func chapters(for book: NovelBook, source: BookSource?) async throws -> [NovelChapter] {
        if book.isLocal {
            return localChapters(book: book)
        }
        guard let source else { throw NovelError.ruleUnsupported("书源不存在") }
        guard source.supportsNativeEngine else {
            throw NovelError.ruleUnsupported("该书源含 JS，暂无法拉取目录")
        }
        let base = URL(string: source.bookSourceUrl)
        var tocURL = book.bookURL
        // Optional bookInfo tocUrl
        if let info = source.ruleBookInfo, let tocRule = info.tocUrl, !tocRule.isEmpty {
            let page = try await NovelNetworkClient.fetchURL(book.bookURL, base: base, source: source)
            let resolved = LegadoRuleEngine.getString(rule: tocRule, in: page, baseURL: base)
            if !resolved.isEmpty { tocURL = resolved }
        }
        let html = try await NovelNetworkClient.fetchURL(tocURL, base: base, source: source)
        guard let toc = source.ruleToc, let listRule = toc.chapterList, !listRule.isEmpty else {
            throw NovelError.noChapters
        }
        let frags = LegadoRuleEngine.getList(rule: listRule, in: html)
        let chapters: [NovelChapter] = frags.compactMap { frag in
            let name = LegadoRuleEngine.getString(rule: toc.chapterName, in: frag, baseURL: base)
            let url = LegadoRuleEngine.getString(rule: toc.chapterUrl, in: frag, baseURL: base)
            guard !name.isEmpty else { return nil }
            return NovelChapter(name: name, url: url.isEmpty ? book.bookURL : url)
        }
        if chapters.isEmpty { throw NovelError.noChapters }
        return chapters
    }

    static func content(
        chapter: NovelChapter,
        book: NovelBook,
        source: BookSource?,
        allLocalChapters: [NovelChapter] = []
    ) async throws -> String {
        if book.isLocal {
            return try localChapterContent(book: book, chapter: chapter, chapters: allLocalChapters)
        }
        guard let source else { throw NovelError.ruleUnsupported("书源不存在") }
        guard source.supportsNativeEngine else {
            throw NovelError.ruleUnsupported("该书源含 JS，暂无法拉取正文")
        }
        let base = URL(string: source.bookSourceUrl)
        let html = try await NovelNetworkClient.fetchURL(chapter.url, base: base, source: source)
        let rule = source.ruleContent?.content
        var text = LegadoRuleEngine.getString(rule: rule, in: html, baseURL: base)
        if text.isEmpty {
            // Fallback: strip article-like body
            text = LegadoRuleEngine.getString(rule: "#content@text||.content@text||#chaptercontent@text", in: html, baseURL: base)
        }
        if let rep = source.ruleContent?.replaceRegex, !rep.isEmpty {
            text = LegadoRuleEngine.getString(rule: "@text##\(rep)##", in: text, baseURL: base)
        }
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw NovelError.emptyContent }
        return text
    }

    // MARK: - Local TXT

    static func localChapters(book: NovelBook) -> [NovelChapter] {
        guard let text = NovelShelfStore.shared.localText(for: book) else {
            return [NovelChapter(name: "全文", url: "local:0")]
        }
        let parts = splitChapters(text)
        if parts.count <= 1 {
            return [NovelChapter(name: "全文", url: "local:0")]
        }
        return parts.enumerated().map { i, part in
            NovelChapter(name: part.title, url: "local:\(i)")
        }
    }

    private static func localChapterContent(
        book: NovelBook,
        chapter: NovelChapter,
        chapters: [NovelChapter]
    ) throws -> String {
        guard let text = NovelShelfStore.shared.localText(for: book) else {
            throw NovelError.emptyContent
        }
        let parts = splitChapters(text)
        if parts.count <= 1 { return text }
        let idx: Int = {
            if chapter.url.hasPrefix("local:"),
               let n = Int(chapter.url.dropFirst("local:".count)) {
                return n
            }
            return chapters.firstIndex(where: { $0.url == chapter.url }) ?? 0
        }()
        guard parts.indices.contains(idx) else { throw NovelError.emptyContent }
        return parts[idx].body
    }

    private static func splitChapters(_ text: String) -> [(title: String, body: String)] {
        let pattern = #"(?m)^(第[\d一二三四五六七八九十百千零〇两]+[章节回卷部集].*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [("全文", text)]
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return [("全文", text)] }

        var result: [(String, String)] = []
        // Preface
        if let first = matches.first, first.range.location > 0 {
            let pre = ns.substring(to: first.range.location)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if pre.count > 40 {
                result.append(("前言", pre))
            }
        }
        for (i, m) in matches.enumerated() {
            let title = ns.substring(with: m.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let start = m.range.location + m.range.length
            let end = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.append((title, body.isEmpty ? "（本章暂无内容）" : body))
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
