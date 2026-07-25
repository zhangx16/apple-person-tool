import Foundation

/// Minimal Legado rule interpreter: JSONPath-ish + CSS-like selectors + `##` replace.
/// Full JS (`<js>` / `@js` / java.*) is not executed; callers should skip such sources.
enum LegadoRuleEngine {

    // MARK: - Public extract

    /// Apply a field rule against a fragment (HTML or JSON text).
    static func getString(rule: String?, in fragment: String, baseURL: URL?) -> String {
        guard let rule, !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        // Join multiple rules with &&
        if rule.contains("&&") {
            let parts = splitTopLevel(rule, separator: "&&")
            return parts
                .map { getString(rule: $0, in: fragment, baseURL: baseURL) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        // Or-list with || — first non-empty
        if rule.contains("||") {
            for part in splitTopLevel(rule, separator: "||") {
                let v = getString(rule: part, in: fragment, baseURL: baseURL)
                if !v.isEmpty { return v }
            }
            return ""
        }

        let (selector, transforms) = splitTransforms(rule)
        var value = extractOnce(selector: selector, in: fragment, baseURL: baseURL)
        for t in transforms {
            value = applyTransform(t, to: value, baseURL: baseURL)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// List of item HTML/JSON fragments for a list rule (e.g. bookList / chapterList).
    static func getList(rule: String?, in document: String) -> [String] {
        guard let rule, !rule.isEmpty else { return [] }
        if rule.trimmingCharacters(in: .whitespaces).hasPrefix("$") {
            return jsonList(path: rule, in: document)
        }
        return htmlList(selector: rule, in: document)
    }

    // MARK: - Transform ##regex##replace###

    private static func splitTransforms(_ rule: String) -> (String, [String]) {
        // Legado: selector##regex##replacement###optional
        guard let range = rule.range(of: "##") else {
            return (rule.trimmingCharacters(in: .whitespaces), [])
        }
        let selector = String(rule[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rest = String(rule[range.upperBound...])
        // Support chained ##
        var transforms: [String] = []
        var current = rest
        while !current.isEmpty {
            if let end = current.range(of: "###") {
                transforms.append(String(current[..<end.lowerBound]))
                current = String(current[end.upperBound...])
                break
            }
            // single ##regex##repl
            if let mid = current.range(of: "##") {
                let regex = String(current[..<mid.lowerBound])
                let repl = String(current[mid.upperBound...])
                transforms.append(regex + "##" + repl)
                break
            } else {
                transforms.append(current)
                break
            }
        }
        return (selector, transforms)
    }

    private static func applyTransform(_ t: String, to value: String, baseURL: URL?) -> String {
        if t.contains("##") {
            let parts = t.components(separatedBy: "##")
            let pattern = parts[0]
            let repl = parts.count > 1 ? parts[1] : ""
            if pattern.isEmpty { return value }
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(value.startIndex..., in: value)
                return regex.stringByReplacingMatches(in: value, range: range, withTemplate: repl)
            }
            return value.replacingOccurrences(of: pattern, with: repl)
        }
        // All-remove mode when only regex given
        if let regex = try? NSRegularExpression(pattern: t, options: []) {
            let range = NSRange(value.startIndex..., in: value)
            return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
        }
        return value
    }

    // MARK: - Extract once

    private static func extractOnce(selector: String, in fragment: String, baseURL: URL?) -> String {
        let sel = selector.trimmingCharacters(in: .whitespaces)
        if sel.hasPrefix("$") {
            return jsonString(path: sel, in: fragment)
        }
        // attr form: rule@href / rule@text / rule@textNodes / rule@ownText / rule@src
        let attr: String
        let css: String
        if let at = sel.range(of: "@", options: .backwards) {
            css = String(sel[..<at.lowerBound])
            attr = String(sel[at.upperBound...])
        } else {
            css = sel
            attr = "text"
        }
        let nodes = htmlList(selector: css, in: fragment)
        guard let first = nodes.first else { return "" }
        switch attr.lowercased() {
        case "href", "src", "data-original", "data-echo", "data-src":
            let v = attribute(attr, of: first)
            return absolutize(v, base: baseURL)
        case "text", "textnodes":
            return stripTags(first)
        case "owntext":
            return ownText(first)
        case "html":
            return first
        default:
            let v = attribute(attr, of: first)
            return v.isEmpty ? stripTags(first) : absolutize(v, base: baseURL)
        }
    }

    // MARK: - JSON

    private static func jsonString(path: String, in text: String) -> String {
        guard let json = parseJSON(text) else { return "" }
        let values = jsonPath(path, on: json)
        if let s = values.first as? String { return s }
        if let n = values.first as? NSNumber { return n.stringValue }
        if let s = values.first { return "\(s)" }
        return ""
    }

    private static func jsonList(path: String, in text: String) -> [String] {
        guard let json = parseJSON(text) else { return [] }
        let values = jsonPath(path, on: json)
        return values.compactMap { item -> String? in
            if let s = item as? String { return s }
            if JSONSerialization.isValidJSONObject(item),
               let data = try? JSONSerialization.data(withJSONObject: item),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            return nil
        }
    }

    private static func parseJSON(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Supports `$.a.b`, `$.list[*]`, `$.data.book_list` (no deep recursive).
    private static func jsonPath(_ path: String, on root: Any) -> [Any] {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("$.") { p = String(p.dropFirst(2)) }
        else if p.hasPrefix("$") { p = String(p.dropFirst()) }
        if p.isEmpty { return [root] }

        var current: [Any] = [root]
        let parts = p.split(separator: ".").map(String.init)
        for part in parts {
            let name: String
            let wantArray: Bool
            if part.hasSuffix("[*]") {
                name = String(part.dropLast(3))
                wantArray = true
            } else {
                name = part
                wantArray = false
            }
            var next: [Any] = []
            for node in current {
                guard let dict = node as? [String: Any] else { continue }
                guard let value = dict[name] else { continue }
                if wantArray, let arr = value as? [Any] {
                    next.append(contentsOf: arr)
                } else if let arr = value as? [Any], !wantArray {
                    // Allow bare array fields
                    next.append(contentsOf: arr)
                } else {
                    next.append(value)
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current
    }

    // MARK: - HTML CSS-like

    /// Selector examples: `.book-li`, `div.item`, `a.0`, `tbody tr!0`, `li.2`
    private static func htmlList(selector: String, in html: String) -> [String] {
        var sel = selector.trimmingCharacters(in: .whitespaces)
        // Drop @attr if accidentally included
        if let at = sel.range(of: "@") {
            sel = String(sel[..<at.lowerBound])
        }

        // Exclude first N: `ul!0` or `tr!0`
        var excludeFirst = 0
        if let bang = sel.range(of: "!", options: .backwards),
           let n = Int(sel[bang.upperBound...]) {
            excludeFirst = n + 1 // !0 means drop index 0
            sel = String(sel[..<bang.lowerBound])
        }

        // Index: `a.0` / `li.2` — last `.digits`
        var index: Int?
        if let dot = sel.range(of: ".", options: .backwards) {
            let tail = String(sel[dot.upperBound...])
            if let n = Int(tail), tail == "\(n)" {
                index = n
                sel = String(sel[..<dot.lowerBound])
            }
        }

        let all = selectElements(sel, in: html)
        var result = all
        if excludeFirst > 0, result.count > excludeFirst {
            result = Array(result.dropFirst(excludeFirst))
        } else if excludeFirst > 0 {
            result = []
        }
        if let index {
            if index >= 0, index < result.count {
                return [result[index]]
            }
            return []
        }
        return result
    }

    private static func selectElements(_ selector: String, in html: String) -> [String] {
        let sel = selector.trimmingCharacters(in: .whitespaces)
        if sel.isEmpty { return [html] }

        // Multi-level space separated: take last token on previous results (simplified)
        let tokens = sel.split(whereSeparator: { $0 == " " || $0 == ">" }).map(String.init)
        var pool = [html]
        for token in tokens {
            var next: [String] = []
            for frag in pool {
                next.append(contentsOf: selectSingle(token, in: frag))
            }
            pool = next
            if pool.isEmpty { break }
        }
        return pool
    }

    private static func selectSingle(_ token: String, in html: String) -> [String] {
        var t = token.trimmingCharacters(in: .whitespaces)
        // Legado aliases: class.xxx / tag.xxx / id.xxx / @css:selector
        if t.hasPrefix("@css:") {
            t = String(t.dropFirst(5))
        }
        if t.hasPrefix("class.") {
            t = "." + String(t.dropFirst(6))
        } else if t.hasPrefix("tag.") {
            t = String(t.dropFirst(4))
        } else if t.hasPrefix("id.") {
            t = "#" + String(t.dropFirst(3))
        }
        if t.hasPrefix(".") {
            let cls = String(t.dropFirst())
            // class may be "foo.0" with index already stripped by htmlList
            return elementsWithClass(cls, in: html)
        }
        if t.hasPrefix("#") {
            let id = String(t.dropFirst())
            return elementsWithID(id, in: html)
        }
        // tag[attr=value] / tag[attr*=value]
        if let bracket = t.firstIndex(of: "["), t.hasSuffix("]") {
            let tag = String(t[..<bracket])
            let inside = String(t[t.index(after: bracket)..<t.index(before: t.endIndex)])
            return elementsWithAttr(tag: tag.isEmpty ? nil : tag, attrExpr: inside, in: html)
        }
        // tag or tag.class
        var tag = t
        var cls: String?
        if let dot = t.firstIndex(of: ".") {
            tag = String(t[..<dot])
            cls = String(t[t.index(after: dot)...])
        }
        return elements(tag: tag.isEmpty ? nil : tag, className: cls, in: html)
    }

    /// Supports `attr=value`, `attr*=value`, `attr^=value`, `attr$=value`.
    private static func elementsWithAttr(tag: String?, attrExpr: String, in html: String) -> [String] {
        let expr = attrExpr.trimmingCharacters(in: .whitespaces)
        let name: String
        let mode: String
        let value: String
        if let r = expr.range(of: "*=") {
            name = String(expr[..<r.lowerBound]); mode = "*"; value = trimQuotes(String(expr[r.upperBound...]))
        } else if let r = expr.range(of: "^=") {
            name = String(expr[..<r.lowerBound]); mode = "^"; value = trimQuotes(String(expr[r.upperBound...]))
        } else if let r = expr.range(of: "$=") {
            name = String(expr[..<r.lowerBound]); mode = "$"; value = trimQuotes(String(expr[r.upperBound...]))
        } else if let r = expr.range(of: "=") {
            name = String(expr[..<r.lowerBound]); mode = "="; value = trimQuotes(String(expr[r.upperBound...]))
        } else {
            return elements(tag: tag, className: nil, in: html)
        }
        let tagPat = tag.map { NSRegularExpression.escapedPattern(for: $0) } ?? "[a-zA-Z0-9]+"
        let pattern = #"<(\#(tagPat))([^>]*)>([\s\S]*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m -> String? in
            let full = ns.substring(with: m.range)
            let attrVal = attribute(name.trimmingCharacters(in: .whitespaces), of: full)
            let ok: Bool
            switch mode {
            case "*": ok = attrVal.contains(value)
            case "^": ok = attrVal.hasPrefix(value)
            case "$": ok = attrVal.hasSuffix(value)
            default: ok = attrVal == value
            }
            return ok ? full : nil
        }
    }

    private static func trimQuotes(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }

    private static func elementsWithClass(_ className: String, in html: String) -> [String] {
        elements(tag: nil, className: className, in: html)
    }

    private static func elementsWithID(_ id: String, in html: String) -> [String] {
        let pattern = #"<([a-zA-Z0-9]+)([^>]*\sid\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: id))["'][^>]*)>([\s\S]*?)</\1>"#
        return matchBlocks(pattern: pattern, in: html)
    }

    private static func elements(tag: String?, className: String?, in html: String) -> [String] {
        let tagPat = tag.map { NSRegularExpression.escapedPattern(for: $0) } ?? "[a-zA-Z0-9]+"
        var classPat = ""
        if let className {
            let c = NSRegularExpression.escapedPattern(for: className)
            classPat = #"(?=[^>]*class\s*=\s*["'][^"']*\#(c)[^"']*["'])"#
        }
        // Non-greedy outer match — good enough for list items
        let pattern = #"<(\#(tagPat))\#(classPat)([^>]*)>([\s\S]*?)</\1>"#
        return matchBlocks(pattern: pattern, in: html)
    }

    private static func matchBlocks(pattern: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        return matches.map { ns.substring(with: $0.range) }
    }

    private static func attribute(_ name: String, of elementHTML: String) -> String {
        let patterns = [
            #"\#(name)\s*=\s*"([^"]*)""#,
            #"\#(name)\s*=\s*'([^']*)'"#,
            #"\#(name)\s*=\s*([^\s>]+)"#
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let m = regex.firstMatch(in: elementHTML, range: NSRange(elementHTML.startIndex..., in: elementHTML)),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: elementHTML) {
                return String(elementHTML[r])
            }
        }
        return ""
    }

    private static func stripTags(_ html: String) -> String {
        var s = html
        // script/style
        if let re = try? NSRegularExpression(pattern: #"<script[\s\S]*?</script>"#, options: .caseInsensitive) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: #"<style[\s\S]*?</style>"#, options: .caseInsensitive) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        // Preserve paragraph breaks
        s = s.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        if let re = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: []) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return decodeEntities(s)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ownText(_ elementHTML: String) -> String {
        // Text before first child tag
        if let open = elementHTML.range(of: ">") {
            let rest = elementHTML[open.upperBound...]
            if let child = rest.range(of: "<") {
                return decodeEntities(String(rest[..<child.lowerBound]))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let close = rest.range(of: "</") {
                return decodeEntities(String(rest[..<close.lowerBound]))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return stripTags(elementHTML)
    }

    private static func decodeEntities(_ s: String) -> String {
        var r = s
        let map = [
            "&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&amp;": "&",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "<br>": "\n", "<br/>": "\n", "<br />": "\n",
            "</p>": "\n", "</div>": "\n"
        ]
        for (k, v) in map { r = r.replacingOccurrences(of: k, with: v) }
        return r
    }

    private static func absolutize(_ url: String, base: URL?) -> String {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("data:") {
            return t
        }
        guard let base else { return t }
        if t.hasPrefix("//") {
            return (base.scheme ?? "https") + ":" + t
        }
        return URL(string: t, relativeTo: base)?.absoluteString ?? t
    }

    private static func splitTopLevel(_ rule: String, separator: String) -> [String] {
        // Simple split (Legado rarely nests && inside quotes for our subset)
        rule.components(separatedBy: separator).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }
}
