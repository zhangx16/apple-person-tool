import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(Int, String)
    case decoding(Error)
    case unauthorized
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的服务器地址"
        case .invalidResponse: return "服务器响应无效"
        case .http(let code, let body):
            if body.isEmpty { return "请求失败 (\(code))" }
            return "请求失败 (\(code)): \(body)"
        case .decoding(let error): return "数据解析失败: \(error.localizedDescription)"
        case .unauthorized: return "未授权，请检查密钥或重新登录"
        case .message(let text): return text
        }
    }
}

/// Request/resource timeout profiles for REST vs long-lived SSE.
enum TimeoutProfile {
    /// Typical JSON REST: request 30s, resource 60s.
    case rest
    /// Streaming chat / long polls: request 120s, resource 600s.
    case sse

    var requestTimeout: TimeInterval {
        switch self {
        case .rest: return 30
        case .sse: return 120
        }
    }

    var resourceTimeout: TimeInterval {
        switch self {
        case .rest: return 60
        case .sse: return 600
        }
    }

    func apply(to configuration: URLSessionConfiguration) {
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
    }
}

final class NetworkClient: @unchecked Sendable {
    static let shared = NetworkClient()

    /// Default REST session (no cookies).
    let session: URLSession
    /// Long-lived SSE / streaming session.
    private let sseSession: URLSession
    /// Mail session with isolated cookie jar (not `HTTPCookieStorage.shared`).
    private let cookieSession: URLSession
    /// App-owned cookie storage for mail sessions; safe to clear on logout.
    let cookieStorage: HTTPCookieStorage

    private static let errorBodyLimit = 400

    private init() {
        let restConfig = URLSessionConfiguration.default
        TimeoutProfile.rest.apply(to: restConfig)
        restConfig.waitsForConnectivity = true
        session = URLSession(configuration: restConfig)

        let sseConfig = URLSessionConfiguration.default
        TimeoutProfile.sse.apply(to: sseConfig)
        sseConfig.waitsForConnectivity = true
        sseSession = URLSession(configuration: sseConfig)

        let isolatedCookies = HTTPCookieStorage()
        cookieStorage = isolatedCookies
        let cookieConfig = URLSessionConfiguration.default
        TimeoutProfile.rest.apply(to: cookieConfig)
        cookieConfig.httpCookieStorage = isolatedCookies
        cookieConfig.httpCookieAcceptPolicy = .always
        cookieConfig.httpShouldSetCookies = true
        cookieConfig.waitsForConnectivity = true
        cookieSession = URLSession(configuration: cookieConfig)
    }

    /// Truncate error response bodies so toast / logs stay readable.
    static func truncatedErrorBody(_ data: Data, limit: Int = errorBodyLimit) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        return truncatedErrorBody(text, limit: limit)
    }

    static func truncatedErrorBody(_ text: String, limit: Int = errorBodyLimit) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit))
    }

    func makeURL(_ base: String, path: String, query: [URLQueryItem] = []) throws -> URL {
        var raw = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasSuffix("/") { raw.removeLast() }
        let full = path.hasPrefix("/") ? raw + path : raw + "/" + path
        guard var components = URLComponents(string: full) else { throw NetworkError.invalidURL }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw NetworkError.invalidURL }
        return url
    }

    func data(
        base: String,
        path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        query: [URLQueryItem] = [],
        useCookies: Bool = false,
        profile: TimeoutProfile = .rest
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(base, path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = profile.requestTimeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if body != nil && request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let chosen: URLSession
        if useCookies {
            chosen = cookieSession
        } else {
            chosen = profile == .sse ? sseSession : session
        }
        let (data, response) = try await chosen.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        return (data, http)
    }

    func json<T: Decodable>(
        _ type: T.Type,
        base: String,
        path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Encodable? = nil,
        query: [URLQueryItem] = [],
        useCookies: Bool = false,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let bodyData = try body.map { try JSONEncoder().encode(AnyEncodable($0)) }
        let (data, http) = try await data(
            base: base,
            path: path,
            method: method,
            headers: headers,
            body: bodyData,
            query: query,
            useCookies: useCookies,
            profile: .rest
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, Self.truncatedErrorBody(data))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    func stream(
        base: String,
        path: String,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Data?
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let url = try makeURL(base, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = TimeoutProfile.sse.requestTimeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if body != nil && request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await sseSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            var collected = Data()
            for try await b in bytes {
                collected.append(b)
                // Collect a little past the display limit so truncation is meaningful.
                if collected.count > Self.errorBodyLimit * 2 { break }
            }
            throw NetworkError.http(http.statusCode, Self.truncatedErrorBody(collected))
        }
        return (bytes, http)
    }

    /// Clears cookies in the isolated mail cookie jar (e.g. on logout).
    func clearCookies() {
        cookieStorage.cookies?.forEach { cookieStorage.deleteCookie($0) }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ value: Encodable) {
        encodeFunc = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
