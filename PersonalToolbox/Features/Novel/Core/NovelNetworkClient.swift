import Foundation

/// HTTP helper for Legado searchUrl forms.
enum NovelNetworkClient {
    struct RequestSpec {
        var url: URL
        var method: String
        var headers: [String: String]
        var body: Data?
        var charsetName: String?
    }

    static func buildSearchRequest(
        source: BookSource,
        key: String,
        page: Int
    ) throws -> RequestSpec {
        guard let searchUrl = source.searchUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !searchUrl.isEmpty else {
            throw NovelError.noSearchURL
        }
        let base = URL(string: source.bookSourceUrl)
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let raw = searchUrl
            .replacingOccurrences(of: "{{key}}", with: encodedKey)
            .replacingOccurrences(of: "{{page}}", with: "\(page)")

        // Form: path,{json options}
        if let comma = raw.firstIndex(of: ","),
           raw[raw.index(after: comma)...].trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            let pathPart = String(raw[..<comma]).trimmingCharacters(in: .whitespaces)
            let jsonPart = String(raw[raw.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            let pathURL = resolve(pathPart, base: base)
            guard let url = pathURL else { throw NovelError.badURL(pathPart) }
            var method = "GET"
            var body: Data?
            var headers: [String: String] = defaultHeaders(source: source, base: base)
            var charset: String?
            if let obj = Self.parseLooseJSONObject(jsonPart) {
                if let m = obj["method"] as? String { method = m.uppercased() }
                if let b = obj["body"] as? String {
                    let bodyStr = b
                        .replacingOccurrences(of: "{{key}}", with: encodedKey)
                        .replacingOccurrences(of: "{{page}}", with: "\(page)")
                    body = bodyStr.data(using: .utf8)
                    if headers["Content-Type"] == nil {
                        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
                    }
                }
                if let h = obj["headers"] as? [String: String] {
                    for (k, v) in h { headers[k] = v }
                } else if let h = obj["headers"] as? [String: Any] {
                    for (k, v) in h { headers[k] = "\(v)" }
                }
                if let c = obj["charset"] as? String { charset = c }
            }
            return RequestSpec(url: url, method: method, headers: headers, body: body, charsetName: charset)
        }

        // Plain URL / path
        guard let url = resolve(raw, base: base) else { throw NovelError.badURL(raw) }
        return RequestSpec(
            url: url,
            method: "GET",
            headers: defaultHeaders(source: source, base: base),
            body: nil,
            charsetName: nil
        )
    }

    static func fetch(
        _ spec: RequestSpec,
        session: URLSession = .shared
    ) async throws -> String {
        var request = URLRequest(url: spec.url)
        request.httpMethod = spec.method
        request.httpBody = spec.body
        request.timeoutInterval = 25
        for (k, v) in spec.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NovelError.network("无响应") }
        guard (200...399).contains(http.statusCode) else {
            throw NovelError.network("HTTP \(http.statusCode)")
        }
        if let name = spec.charsetName?.lowercased(),
           name.contains("gb") || name.contains("gbk") || name.contains("gb2312") {
            // Rough GBK decode via CF
            let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let s = NSString(data: data, encoding: cf) as String? {
                return s
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw NovelError.network("无法解码响应")
    }

    static func fetchURL(
        _ urlString: String,
        base: URL?,
        source: BookSource?
    ) async throws -> String {
        guard let url = resolve(urlString, base: base) else { throw NovelError.badURL(urlString) }
        let headers = defaultHeaders(source: source, base: base)
        return try await fetch(RequestSpec(url: url, method: "GET", headers: headers, body: nil, charsetName: nil))
    }

    private static func resolve(_ path: String, base: URL?) -> URL? {
        let t = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            return URL(string: t)
        }
        guard let base else { return URL(string: t) }
        if t.hasPrefix("//") {
            return URL(string: (base.scheme ?? "https") + ":" + t)
        }
        return URL(string: t, relativeTo: base)?.absoluteURL
    }

    private static func defaultHeaders(source: BookSource?, base: URL?) -> [String: String] {
        var h: [String: String] = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            "Accept": "text/html,application/json,*/*",
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
        if let base {
            h["Referer"] = base.absoluteString
        }
        if let header = source?.header,
           let data = header.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (k, v) in obj { h[k] = v }
        }
        return h
    }

    /// Legado often uses single-quoted JSON in searchUrl options.
    private static func parseLooseJSONObject(_ raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        // crude single-quote → double-quote for simple option objects
        var s = trimmed
        s = s.replacingOccurrences(of: #"^\s*'"#, with: "\"", options: .regularExpression)
        // replace 'key': with "key":
        if let re = try? NSRegularExpression(pattern: #"'([^']*)'"#, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "\"$1\"")
        }
        if let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return nil
    }
}

enum NovelError: LocalizedError {
    case noSearchURL
    case badURL(String)
    case network(String)
    case ruleUnsupported(String)
    case noChapters
    case emptyContent
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSearchURL: return "该书源未配置搜索地址"
        case .badURL(let s): return "无效链接：\(s)"
        case .network(let s): return "网络错误：\(s)"
        case .ruleUnsupported(let s): return "规则暂不支持：\(s)"
        case .noChapters: return "未解析到章节"
        case .emptyContent: return "正文为空"
        case .importFailed(let s): return "导入失败：\(s)"
        }
    }
}
