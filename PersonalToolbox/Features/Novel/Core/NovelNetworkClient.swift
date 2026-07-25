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

    /// Session that allows cleartext + a bounded redirect budget (novel sites often hop http↔https).
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 28
        config.timeoutIntervalForResource = 40
        config.httpMaximumConnectionsPerHost = 6
        config.httpShouldUsePipelining = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Do not compress; some GBK sites mishandle br/gzip negotiation.
        config.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
        return URLSession(configuration: config, delegate: RedirectLimiter(), delegateQueue: nil)
    }()

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
        // Default UTF-8 encode; overridden when options declare charset=gbk.
        var charsetHint: String?
        var encodedKey = percentEncode(key, charset: nil)
        let pageStr = "\(page)"

        // Form: path,{json options}  — require comma *and* `{` so `q={{key}}` is not misparsed.
        if let comma = searchUrl.firstIndex(of: ","),
           searchUrl[searchUrl.index(after: comma)...].trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            let pathPart = String(searchUrl[..<comma]).trimmingCharacters(in: .whitespaces)
            let jsonPart = String(searchUrl[searchUrl.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            var method = "GET"
            var body: Data?
            var headers: [String: String] = defaultHeaders(source: source, base: base)
            if let obj = Self.parseLooseJSONObject(jsonPart) {
                if let m = obj["method"] as? String { method = m.uppercased() }
                if let c = obj["charset"] as? String {
                    charsetHint = c
                    encodedKey = percentEncode(key, charset: c)
                }
                if let b = obj["body"] as? String {
                    let bodyStr = b
                        .replacingOccurrences(of: "{{key}}", with: encodedKey)
                        .replacingOccurrences(of: "{{page}}", with: pageStr)
                    if let cs = charsetHint, cs.lowercased().contains("gb") {
                        body = gbkData(from: bodyStr) ?? bodyStr.data(using: .utf8)
                    } else {
                        body = bodyStr.data(using: .utf8)
                    }
                    if headers["Content-Type"] == nil {
                        let cs = (charsetHint?.lowercased().contains("gb") == true) ? "gbk" : "utf-8"
                        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=\(cs)"
                    }
                }
                if let h = obj["headers"] as? [String: String] {
                    for (k, v) in h { headers[k] = v }
                } else if let h = obj["headers"] as? [String: Any] {
                    for (k, v) in h { headers[k] = "\(v)" }
                }
            }
            let pathExpanded = pathPart
                .replacingOccurrences(of: "{{key}}", with: encodedKey)
                .replacingOccurrences(of: "{{page}}", with: pageStr)
            guard let url = resolve(pathExpanded, base: base) else { throw NovelError.badURL(pathExpanded) }
            return RequestSpec(url: url, method: method, headers: headers, body: body, charsetName: charsetHint)
        }

        // Plain URL / path — still allow optional trailing options without body via charset in source header
        let raw = searchUrl
            .replacingOccurrences(of: "{{key}}", with: encodedKey)
            .replacingOccurrences(of: "{{page}}", with: pageStr)
        guard let url = resolve(raw, base: base) else { throw NovelError.badURL(raw) }
        return RequestSpec(
            url: url,
            method: "GET",
            headers: defaultHeaders(source: source, base: base),
            body: nil,
            charsetName: charsetHint
        )
    }

    static func fetch(
        _ spec: RequestSpec,
        session: URLSession? = nil
    ) async throws -> String {
        let sess = session ?? Self.session
        var request = URLRequest(url: spec.url)
        request.httpMethod = spec.method
        request.httpBody = spec.body
        request.timeoutInterval = 28
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (k, v) in spec.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sess.data(for: request)
        } catch {
            throw mapTransportError(error, url: spec.url)
        }
        guard let http = response as? HTTPURLResponse else { throw NovelError.network("无响应") }
        // Some sites return 200 with empty / challenge body; surface HTTP errors clearly.
        guard (200...399).contains(http.statusCode) else {
            if http.statusCode == 403 {
                throw NovelError.network("HTTP 403（站点拒绝访问，可换书源）")
            }
            throw NovelError.network("HTTP \(http.statusCode)")
        }
        if data.isEmpty {
            throw NovelError.network("空响应")
        }
        return decodeBody(data, charsetName: spec.charsetName, response: http)
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

    // MARK: - Encoding / resolve

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
            // Desktop Chrome UA — mobile UA triggers more 403 / WAF on novel mirrors.
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Accept-Encoding": "identity",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1"
        ]
        if let base {
            h["Referer"] = base.absoluteString.hasSuffix("/")
                ? base.absoluteString
                : base.absoluteString + "/"
        }
        if let header = source?.header,
           let data = header.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (k, v) in obj { h[k] = v }
        } else if let header = source?.header,
                  let data = header.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj { h[k] = "\(v)" }
        }
        return h
    }

    /// Percent-encode for query/body. Uses GBK when charset hints GB family.
    private static func percentEncode(_ raw: String, charset: String?) -> String {
        let cs = (charset ?? "").lowercased()
        if cs.contains("gb") {
            if let data = gbkData(from: raw) {
                return data.map { byte -> String in
                    // Unreserved for form/query
                    let b = byte
                    if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
                        || b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E {
                        return String(UnicodeScalar(b))
                    }
                    return String(format: "%%%02X", b)
                }.joined()
            }
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    private static func gbkData(from string: String) -> Data? {
        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return (string as NSString).data(using: enc)
    }

    private static func decodeBody(_ data: Data, charsetName: String?, response: HTTPURLResponse) -> String {
        let hinted = (charsetName ?? response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if hinted.contains("gb") || hinted.contains("gbk") || hinted.contains("gb2312") {
            let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let s = NSString(data: data, encoding: cf) as String? { return s }
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            // Some GBK pages mislabeled as utf-8 produce lots of replacement chars — retry GBK.
            let replacements = utf8.filter { $0 == "\u{FFFD}" }.count
            if replacements > 8 || (utf8.count > 200 && replacements * 20 > utf8.count) {
                let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                if let s = NSString(data: data, encoding: cf) as String? { return s }
            }
            return utf8
        }
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = NSString(data: data, encoding: cf) as String? { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    private static func mapTransportError(_ error: Error, url: URL) -> NovelError {
        let ns = error as NSError
        let desc = ns.localizedDescription
        // ATS
        if desc.localizedCaseInsensitiveContains("App Transport Security")
            || desc.localizedCaseInsensitiveContains("secure connection")
            || ns.code == -1022 {
            return .network("不安全 HTTP 被拦截（ATS）。请更新 App 或换 HTTPS 书源。")
        }
        if desc.localizedCaseInsensitiveContains("too many HTTP redirects")
            || desc.localizedCaseInsensitiveContains("redirect") && ns.code == -1007 {
            return .network("重定向过多（站点异常），已跳过该书源")
        }
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut: return .network("连接超时")
            case NSURLErrorNotConnectedToInternet: return .network("无网络连接")
            case NSURLErrorCannotFindHost: return .network("域名无法解析")
            case NSURLErrorCannotConnectToHost: return .network("无法连接主机")
            case NSURLErrorServerCertificateUntrusted,
                 NSURLErrorSecureConnectionFailed:
                return .network("HTTPS 证书异常")
            case NSURLErrorHTTPTooManyRedirects:
                return .network("重定向过多（站点异常），已跳过该书源")
            default: break
            }
        }
        return .network(desc)
    }

    /// Legado often uses single-quoted JSON in searchUrl options.
    private static func parseLooseJSONObject(_ raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        var s = trimmed
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

// MARK: - Redirect limiter

/// Caps redirect hops so broken sites (redirect loops) fail fast with a clear error.
private final class RedirectLimiter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let maxRedirects = 6
    private let lock = NSLock()
    private var hops: [Int: Int] = [:]

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        let n = (hops[task.taskIdentifier] ?? 0) + 1
        hops[task.taskIdentifier] = n
        lock.unlock()
        if n > maxRedirects {
            completionHandler(nil)
            return
        }
        var next = request
        if next.value(forHTTPHeaderField: "User-Agent") == nil,
           let ua = task.originalRequest?.value(forHTTPHeaderField: "User-Agent") {
            next.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        hops.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
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
