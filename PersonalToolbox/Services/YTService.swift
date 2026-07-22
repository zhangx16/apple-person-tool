import Foundation

actor YTService {
    static let shared = YTService()
    private let client = NetworkClient.shared
    private var token: String?

    /// Keychain account for optional session token persistence.
    private static let tokenKeychainKey = "ytSessionToken"
    /// UserDefaults key for token save timestamp (seconds since 1970).
    private static let tokenSavedAtKey = "ytTokenSavedAt"
    /// Re-login before backend sessionTTL (7d); refresh at ~6.5 days.
    private static let tokenMaxAge: TimeInterval = 6.5 * 24 * 60 * 60

    init() {
        // Restore token from Keychain if still within soft TTL.
        if let saved = KeychainStore.get(Self.tokenKeychainKey), !saved.isEmpty {
            let savedAt = UserDefaults.standard.double(forKey: Self.tokenSavedAtKey)
            if savedAt > 0 {
                let age = Date().timeIntervalSince1970 - savedAt
                if age < Self.tokenMaxAge {
                    token = saved
                } else {
                    KeychainStore.delete(Self.tokenKeychainKey)
                    UserDefaults.standard.removeObject(forKey: Self.tokenSavedAtKey)
                }
            } else {
                token = saved
            }
        }
    }

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
        let resolved: String?
        if let s = try? JSONDecoder().decode(String.self, from: data) {
            resolved = s
        } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let t = obj["token"] as? String {
            resolved = t
        } else {
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            resolved = (raw?.isEmpty == false) ? raw : nil
        }
        guard let resolved, !resolved.isEmpty else { throw NetworkError.message("登录响应无效") }
        persistToken(resolved)
    }

    private func persistToken(_ value: String) {
        token = value
        KeychainStore.set(value, for: Self.tokenKeychainKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.tokenSavedAtKey)
    }

    private func clearPersistedToken() {
        token = nil
        KeychainStore.delete(Self.tokenKeychainKey)
        UserDefaults.standard.removeObject(forKey: Self.tokenSavedAtKey)
    }

    private func authHeaders() throws -> [String: String] {
        guard let token, !token.isEmpty else { throw NetworkError.unauthorized }
        return ["X-Authentication": token, "Content-Type": "application/json"]
    }

    func ensureLogin(baseURL: String, username: String, password: String) async throws {
        if let token, !token.isEmpty {
            // Soft TTL: re-login if persisted token is older than ~6.5 days.
            let savedAt = UserDefaults.standard.double(forKey: Self.tokenSavedAtKey)
            if savedAt > 0 {
                let age = Date().timeIntervalSince1970 - savedAt
                if age >= Self.tokenMaxAge {
                    clearPersistedToken()
                    try await login(baseURL: baseURL, username: username, password: password)
                }
            }
            return
        }
        try await login(baseURL: baseURL, username: username, password: password)
    }

    /// Drops the in-memory and Keychain auth token (Settings「注销全部会话」).
    func logout() {
        clearPersistedToken()
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
            clearPersistedToken()
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
            // Match yt-dlp-web-ui frontend payload + qualityFormats
            // Pair video+audio and remux mp4 (matches yt-dlp-web-ui). Sort for AVPlayer-friendly codecs.
            let params: [String: Any] = [
                "URL": url,
                "Params": [
                    "--no-playlist",
                    "-f", preset.format,
                    "--merge-output-format", "mp4",
                    // Prefer streams that include audio and H.264 (best AVPlayer compatibility).
                    "-S", "+hasaud,vcodec:h264,res,br"
                ],
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
                // Skip directories when the backend marks them.
                if let isDir = row["isDirectory"] as? Bool, isDir { return nil }
                if let isDir = row["IsDir"] as? Bool, isDir { return nil }
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
                else if let s = row["size"] as? Double { size = Int64(s) }
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

    /// Build download URL. Path segment is **base64.StdEncoding** of the file path,
    /// then percent-encoded (matches frontend `encodedPath` / backend `handleFileDownload`).
    func downloadURL(baseURL: String, path: String) throws -> URL {
        guard let token, !token.isEmpty else { throw NetworkError.unauthorized }
        var raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasSuffix("/") { raw.removeLast() }
        let pathData = Data(path.utf8)
        let b64 = pathData.base64EncodedString() // StdEncoding (default)
        // Match encodeURIComponent: encode + / = and other reserved chars so path
        // segment is a single component (urlPathAllowed keeps `/` which breaks decode).
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        let encoded = b64.addingPercentEncoding(withAllowedCharacters: allowed) ?? b64
        let tokenQ = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        let urlString = "\(raw)/filebrowser/d/\(encoded)?token=\(tokenQ)"
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        return url
    }

    // MARK: - parseTasks

    /// Parse `Service.Running` result. Prefer nested `info` / `progress` / `output`.
    /// process_status: 0 pending, 1 running, **2 completed**, **3 failed**.
    /// percentage `"-1"` means complete → UI 100%.
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
            let info = row["info"] as? [String: Any]
            let progressObj = row["progress"] as? [String: Any]
            let output = row["output"] as? [String: Any]

            let id = (row["id"] as? String)
                ?? (row["Id"] as? String)
                ?? (row["pid"] as? String)
                ?? UUID().uuidString

            let url = (info?["url"] as? String)
                ?? (row["url"] as? String)
                ?? (row["URL"] as? String)
                ?? ""

            let title = (info?["title"] as? String)
                ?? (row["title"] as? String)
                ?? (row["Title"] as? String)
                ?? url

            let thumbnail = info?["thumbnail"] as? String

            // process_status: prefer Int; tolerate Double/String from loose JSON.
            let processStatus: Int = {
                if let v = progressObj?["process_status"] as? Int { return v }
                if let v = progressObj?["process_status"] as? Double { return Int(v) }
                if let v = progressObj?["process_status"] as? String, let i = Int(v) { return i }
                if let v = row["process_status"] as? Int { return v }
                return 0
            }()

            let percentageRaw: String = {
                if let s = progressObj?["percentage"] as? String { return s }
                if let n = progressObj?["percentage"] as? Double {
                    return n < 0 ? "-1" : "\(n)%"
                }
                if let s = row["percentage"] as? String { return s }
                return "0%"
            }()

            let progress = Self.progress01(percentageRaw: percentageRaw, processStatus: processStatus)

            let speed: String = {
                if let n = progressObj?["speed"] as? Double {
                    return Self.formatSpeed(n)
                }
                if let n = progressObj?["speed"] as? Int {
                    return Self.formatSpeed(Double(n))
                }
                if let s = progressObj?["speed"] as? String, !s.isEmpty {
                    return s
                }
                if let s = row["speed"] as? String { return s }
                return ""
            }()

            let eta = (progressObj?["eta"] as? String)
                ?? (row["eta"] as? String)
                ?? ""

            let filepath = (output?["savedFilePath"] as? String)
                ?? (row["filepath"] as? String)
                ?? (row["filename"] as? String)

            let error: String? = {
                if let e = row["error"] as? String, !e.isEmpty { return e }
                return nil
            }()

            let statusLabel: String = {
                switch processStatus {
                case 0: return "等待中"
                case 1: return "下载中"
                case 2: return "已完成"
                case 3: return "失败"
                case 4: return "直播"
                default: return "未知"
                }
            }()

            return YTTask(
                id: id,
                url: url,
                title: title.isEmpty ? url : title,
                status: statusLabel,
                processStatus: processStatus,
                percentageRaw: percentageRaw,
                progress: progress,
                speed: speed,
                eta: eta,
                filepath: filepath,
                error: error,
                thumbnail: thumbnail
            )
        }
    }

    /// Convert backend percentage string to 0...1. `"-1"` or status 2 → 1.0.
    /// Backend always sends percent units (`"45.2%"`, `"1%"`, `"0.5%"`) — never fractions.
    static func progress01(percentageRaw: String, processStatus: Int) -> Double {
        if percentageRaw == "-1" || processStatus == 2 { return 1 }
        if processStatus == 0 { return 0 }
        let trimmed = percentageRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        guard let value = Double(trimmed), value.isFinite else { return 0 }
        // Negative sentinel (other than the string "-1") → complete.
        if value < 0 { return 1 }
        // Always interpret as percent units: "1%" → 0.01, not 1.0.
        return max(0, min(1, value / 100))
    }

    /// Format bytes/s number to human string (e.g. `1.2 MB/s`).
    static func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0, bytesPerSec.isFinite else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(bytesPerSec.rounded())) + "/s"
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
