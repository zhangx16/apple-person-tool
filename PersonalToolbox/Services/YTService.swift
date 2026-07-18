import Foundation

actor YTService {
    static let shared = YTService()
    private let client = NetworkClient.shared
    private var token: String?

    func login(baseURL: String, username: String, password: String) async throws {
        struct Body: Encodable {
            let username: String
            let password: String
        }
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/auth/login",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(Body(username: username, password: password))
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        // Response is a raw JSON string token
        if let s = try? JSONDecoder().decode(String.self, from: data) {
            token = s
            return
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let t = obj["token"] as? String {
            token = t
            return
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard let raw, !raw.isEmpty else { throw NetworkError.message("登录响应无效") }
        token = raw
    }

    private func authHeaders() throws -> [String: String] {
        guard let token, !token.isEmpty else { throw NetworkError.unauthorized }
        return ["X-Authentication": token, "Content-Type": "application/json"]
    }

    func ensureLogin(baseURL: String, username: String, password: String) async throws {
        if token != nil { return }
        try await login(baseURL: baseURL, username: username, password: password)
    }

    /// Drops the in-memory auth token (Settings「注销全部会话」).
    func logout() {
        token = nil
    }

    private func withAuthRetry<T>(
        baseURL: String,
        username: String,
        password: String,
        _ work: () async throws -> T
    ) async throws -> T {
        try await ensureLogin(baseURL: baseURL, username: username, password: password)
        do {
            return try await work()
        } catch NetworkError.unauthorized {
            token = nil
            try await login(baseURL: baseURL, username: username, password: password)
            return try await work()
        }
    }

    func version(baseURL: String, username: String, password: String) async throws -> String {
        try await withAuthRetry(baseURL: baseURL, username: username, password: password) {
            let headers = try authHeaders()
            let (data, http) = try await client.data(
                base: baseURL,
                path: "/api/v1/version",
                headers: headers
            )
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkClient.httpError(status: http.statusCode, body: data)
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (obj["ytdlpVersion"] as? String) ?? "ok"
            }
            return "ok"
        }
    }

    private func rpc(
        baseURL: String,
        method: String,
        params: [Any] = []
    ) async throws -> Any? {
        let headers = try authHeaders()
        let payload: [String: Any] = [
            "method": method,
            "params": params,
            "id": UUID().uuidString
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/rpc/http",
            method: "POST",
            headers: headers,
            body: body
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = obj?["error"] as? String, !err.isEmpty {
            throw NetworkError.message(err)
        }
        return obj?["result"]
    }

    func parseFormats(
        baseURL: String,
        username: String,
        password: String,
        url: String
    ) async throws -> VideoMetadata {
        try await withAuthRetry(baseURL: baseURL, username: username, password: password) {
            let result = try await rpc(baseURL: baseURL, method: "Service.Formats", params: [["URL": url]])
            let dict = result as? [String: Any] ?? [:]
            let title = (dict["title"] as? String)
                ?? (dict["Title"] as? String)
                ?? url
            let duration: String?
            if let d = dict["duration"] as? Double {
                duration = formatDuration(d)
            } else if let d = dict["Duration"] as? Double {
                duration = formatDuration(d)
            } else {
                duration = dict["duration_string"] as? String
            }
            return VideoMetadata(
                title: title,
                duration: duration,
                thumbnail: (dict["thumbnail"] as? String) ?? (dict["Thumbnail"] as? String),
                uploader: (dict["uploader"] as? String) ?? (dict["channel"] as? String)
            )
        }
    }

    func startDownload(
        baseURL: String,
        username: String,
        password: String,
        url: String,
        preset: YTFormatOption
    ) async throws {
        try await withAuthRetry(baseURL: baseURL, username: username, password: password) {
            // Match yt-dlp-web-ui frontend payload
            let params: [String: Any] = [
                "URL": url,
                "Params": ["--no-playlist", "-f", preset.format, "--merge-output-format", "mp4"],
                "Path": "",
                "Rename": ""
            ]
            _ = try await rpc(baseURL: baseURL, method: "Service.Exec", params: [params])
        }
    }

    func runningTasks(
        baseURL: String,
        username: String,
        password: String
    ) async throws -> [YTTask] {
        try await withAuthRetry(baseURL: baseURL, username: username, password: password) {
            let result = try await rpc(baseURL: baseURL, method: "Service.Running")
            return parseTasks(result)
        }
    }

    func killTask(baseURL: String, username: String, password: String, id: String) async throws {
        try await withAuthRetry(baseURL: baseURL, username: username, password: password) {
            _ = try await rpc(baseURL: baseURL, method: "Service.Kill", params: [id])
        }
    }

    func clearTask(baseURL: String, username: String, password: String, id: String) async throws {
        try await withAuthRetry(baseURL: baseURL, username: username, password: password) {
            _ = try await rpc(baseURL: baseURL, method: "Service.Clear", params: [id])
        }
    }

    func listFiles(
        baseURL: String,
        username: String,
        password: String
    ) async throws -> [YTFileItem] {
        try await withAuthRetry(baseURL: baseURL, username: username, password: password) {
            let headers = try authHeaders()
            let (data, http) = try await client.data(
                base: baseURL,
                path: "/filebrowser/downloaded",
                method: "POST",
                headers: headers,
                body: Data("{}".utf8)
            )
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkClient.httpError(status: http.statusCode, body: data)
            }
            let root = try JSONSerialization.jsonObject(with: data)
            let rows: [[String: Any]]
            if let arr = root as? [[String: Any]] {
                rows = arr
            } else if let dict = root as? [String: Any] {
                rows = (dict["files"] as? [[String: Any]])
                    ?? (dict["result"] as? [[String: Any]])
                    ?? (dict["data"] as? [[String: Any]])
                    ?? []
            } else {
                rows = []
            }
            return rows.compactMap { row in
                let name = (row["name"] as? String)
                    ?? (row["Name"] as? String)
                    ?? (row["filename"] as? String)
                    ?? ""
                guard !name.isEmpty else { return nil }
                let path = (row["path"] as? String) ?? (row["Path"] as? String) ?? name
                let size: Int64?
                if let s = row["size"] as? Int64 { size = s }
                else if let s = row["Size"] as? Int64 { size = s }
                else if let s = row["size"] as? Int { size = Int64(s) }
                else { size = nil }
                return YTFileItem(id: path, name: name, size: size, path: path)
            }
        }
    }

    func deleteFile(
        baseURL: String,
        username: String,
        password: String,
        path: String
    ) async throws {
        try await withAuthRetry(baseURL: baseURL, username: username, password: password) {
            let headers = try authHeaders()
            let body = try JSONSerialization.data(withJSONObject: ["path": path])
            let (data, http) = try await client.data(
                base: baseURL,
                path: "/filebrowser/delete",
                method: "POST",
                headers: headers,
                body: body
            )
            if http.statusCode == 401 { throw NetworkError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkClient.httpError(status: http.statusCode, body: data)
            }
        }
    }

    func downloadURL(baseURL: String, path: String) throws -> URL {
        guard let token else { throw NetworkError.unauthorized }
        var raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasSuffix("/") { raw.removeLast() }
        let encodedPath = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let urlString = "\(raw)/filebrowser/d/\(encodedPath)?token=\(token)"
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        return url
    }

    private func parseTasks(_ result: Any?) -> [YTTask] {
        let rows: [[String: Any]]
        if let arr = result as? [[String: Any]] {
            rows = arr
        } else if let dict = result as? [String: Any] {
            rows = (dict["processes"] as? [[String: Any]])
                ?? (dict["tasks"] as? [[String: Any]])
                ?? (dict["items"] as? [[String: Any]])
                ?? Array(dict.values).compactMap { $0 as? [String: Any] }
        } else {
            rows = []
        }

        return rows.compactMap { row in
            let id = (row["id"] as? String)
                ?? (row["Id"] as? String)
                ?? (row["pid"] as? String)
                ?? UUID().uuidString
            let url = (row["url"] as? String) ?? (row["URL"] as? String) ?? ""
            let title = (row["title"] as? String) ?? (row["Title"] as? String) ?? url
            let status = (row["status"] as? String)
                ?? (row["Progress"] as? [String: Any])?["status"] as? String
                ?? "unknown"
            var progress = 0.0
            if let p = row["progress"] as? Double { progress = p > 1 ? p / 100 : p }
            else if let p = row["percentage"] as? Double { progress = p > 1 ? p / 100 : p }
            else if let p = (row["Progress"] as? [String: Any])?["percentage"] as? Double {
                progress = p > 1 ? p / 100 : p
            }
            let speed = (row["speed"] as? String)
                ?? (row["Speed"] as? String)
                ?? ((row["Progress"] as? [String: Any])?["speed"] as? String)
                ?? ""
            let eta = (row["eta"] as? String)
                ?? ((row["Progress"] as? [String: Any])?["eta"] as? String)
                ?? ""
            let filepath = (row["filepath"] as? String) ?? (row["filename"] as? String)
            let error = row["error"] as? String
            return YTTask(
                id: id,
                url: url,
                title: title.isEmpty ? url : title,
                status: status,
                progress: progress,
                speed: speed,
                eta: eta,
                filepath: filepath,
                error: error
            )
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
