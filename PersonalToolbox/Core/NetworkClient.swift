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

final class NetworkClient: @unchecked Sendable {
    static let shared = NetworkClient()

    let session: URLSession
    private let cookieSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)

        let cookieConfig = URLSessionConfiguration.default
        cookieConfig.httpCookieStorage = HTTPCookieStorage.shared
        cookieConfig.httpCookieAcceptPolicy = .always
        cookieConfig.httpShouldSetCookies = true
        cookieConfig.timeoutIntervalForRequest = 120
        cookieConfig.timeoutIntervalForResource = 600
        cookieSession = URLSession(configuration: cookieConfig)
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
        useCookies: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(base, path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if body != nil && request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let chosen = useCookies ? cookieSession : session
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
            useCookies: useCookies
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NetworkError.http(http.statusCode, text.prefix(400).description)
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
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if body != nil && request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw NetworkError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            var collected = Data()
            for try await b in bytes {
                collected.append(b)
                if collected.count > 800 { break }
            }
            let text = String(data: collected, encoding: .utf8) ?? ""
            throw NetworkError.http(http.statusCode, text)
        }
        return (bytes, http)
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
