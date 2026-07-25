import CryptoKit
import Foundation

/// OpenSubsonic / Navidrome REST client (compatible with Subsonic 1.16.1).
@MainActor
final class NavidromeClient {
    static let shared = NavidromeClient()

    enum ClientError: LocalizedError {
        case notConfigured
        case invalidBaseURL
        case server(String)
        case noMatch(title: String, artist: String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "尚未配置 Navidrome（服务器 / 用户名 / 密码）。"
            case .invalidBaseURL:
                return "Navidrome 服务器地址无效。"
            case .server(let msg):
                return "Navidrome：\(msg)"
            case .noMatch(let title, let artist):
                let q = [title, artist].filter { !$0.isEmpty }.joined(separator: " - ")
                return "Navidrome 曲库未找到「\(q)」。"
            case .badResponse:
                return "Navidrome 返回了无法解析的数据。"
            }
        }
    }

    struct SongHit: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let artist: String
        let album: String?
        let duration: Int // seconds
        let bitRate: Int?
        let coverArt: String?
        let contentType: String?
        let suffix: String?
    }

    private let clientName = "PersonalToolbox"
    private let apiVersion = "1.16.1"
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Public

    func ping(settings: MeloXSettings) async throws -> String {
        let json = try await getJSON(action: "ping.view", settings: settings)
        guard let status = json["status"] as? String, status == "ok" else {
            throw ClientError.server(Self.errorMessage(from: json) ?? "ping 失败")
        }
        let type = json["type"] as? String ?? "subsonic"
        let ver = json["serverVersion"] as? String ?? (json["version"] as? String ?? "")
        return "\(type) \(ver)".trimmingCharacters(in: .whitespaces)
    }

    func searchSongs(
        query: String,
        settings: MeloXSettings,
        songCount: Int = 30
    ) async throws -> [SongHit] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let json = try await getJSON(
            action: "search3.view",
            settings: settings,
            extra: [
                "query": term,
                "songCount": String(songCount),
                "albumCount": "0",
                "artistCount": "0",
            ]
        )
        let result = (json["searchResult3"] as? [String: Any]) ?? [:]
        let rawSongs = result["song"] as? [[String: Any]] ?? []
        return rawSongs.compactMap(Self.parseSong)
    }

    /// Best library match for a Netease (or any) track title + artist.
    func bestMatch(
        title: String,
        artist: String,
        settings: MeloXSettings
    ) async throws -> SongHit {
        let cleanedTitle = scrub(title)
        let cleanedArtist = scrub(artist)
        var queries: [String] = []
        let both = [cleanedTitle, cleanedArtist].filter { !$0.isEmpty }.joined(separator: " ")
        if !both.isEmpty { queries.append(both) }
        if !cleanedTitle.isEmpty { queries.append(cleanedTitle) }

        var candidates: [SongHit] = []
        var seen = Set<String>()
        for q in queries {
            let hits = try await searchSongs(query: q, settings: settings, songCount: 40)
            for h in hits where seen.insert(h.id).inserted {
                candidates.append(h)
            }
            if candidates.count >= 8 { break }
        }
        guard !candidates.isEmpty else {
            throw ClientError.noMatch(title: title, artist: artist)
        }

        let ranked = candidates.sorted {
            score($0, title: cleanedTitle, artist: cleanedArtist)
                > score($1, title: cleanedTitle, artist: cleanedArtist)
        }
        guard let best = ranked.first,
              score(best, title: cleanedTitle, artist: cleanedArtist) >= 20
        else {
            // Still return top hit if title loosely matches.
            if let first = ranked.first,
               normalize(first.title).contains(normalize(cleanedTitle))
                || normalize(cleanedTitle).contains(normalize(first.title)) {
                return first
            }
            throw ClientError.noMatch(title: title, artist: artist)
        }
        return best
    }

    func streamURL(songID: String, settings: MeloXSettings) throws -> URL {
        try restURL(
            action: "stream.view",
            settings: settings,
            extra: [
                "id": songID,
                "format": "raw",
            ]
        )
    }

    func coverArtURL(coverArt: String?, settings: MeloXSettings, size: Int = 300) -> URL? {
        guard let coverArt, !coverArt.isEmpty else { return nil }
        return try? restURL(
            action: "getCoverArt.view",
            settings: settings,
            extra: [
                "id": coverArt,
                "size": String(size),
            ]
        )
    }

    func playbackSource(
        title: String,
        artist: String,
        settings: MeloXSettings
    ) async throws -> (source: PlaybackSource, hit: SongHit) {
        let hit = try await bestMatch(title: title, artist: artist, settings: settings)
        let url = try streamURL(songID: hit.id, settings: settings)
        let source = PlaybackSource(
            url: url,
            bitrate: hit.bitRate.map { $0 * 1000 },
            format: hit.suffix,
            isTrialPreview: false
        )
        return (source, hit)
    }

    // MARK: - HTTP

    private func getJSON(
        action: String,
        settings: MeloXSettings,
        extra: [String: String] = [:]
    ) async throws -> [String: Any] {
        let url = try restURL(action: action, settings: settings, extra: extra)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("PersonalToolbox/MeloX", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ClientError.server("HTTP \(http.statusCode)")
        }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sub = root["subsonic-response"] as? [String: Any]
        else {
            throw ClientError.badResponse
        }
        if let status = sub["status"] as? String, status != "ok" {
            throw ClientError.server(Self.errorMessage(from: sub) ?? "请求失败")
        }
        return sub
    }

    private func restURL(
        action: String,
        settings: MeloXSettings,
        extra: [String: String]
    ) throws -> URL {
        let base = settings.navidromeBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let baseURL = URL(string: base) else {
            throw ClientError.invalidBaseURL
        }
        let user = settings.navidromeUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = settings.navidromePassword
        guard !user.isEmpty, !password.isEmpty else {
            throw ClientError.notConfigured
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest").appendingPathComponent(action),
            resolvingAgainstBaseURL: false
        )!
        // Token auth: t = md5(password + salt), avoids putting raw password on some logs.
        let salt = Self.randomSalt()
        let token = Self.md5Hex(password + salt)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "u", value: user),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
        for (k, v) in extra {
            items.append(URLQueryItem(name: k, value: v))
        }
        components.queryItems = items
        guard let url = components.url else { throw ClientError.invalidBaseURL }
        return url
    }

    // MARK: - Parse / match helpers

    private static func parseSong(_ dict: [String: Any]) -> SongHit? {
        guard let id = dict["id"] as? String ?? (dict["id"] as? Int).map(String.init),
              let title = dict["title"] as? String
        else { return nil }
        let artist = (dict["artist"] as? String)
            ?? (dict["displayArtist"] as? String)
            ?? "未知歌手"
        let duration: Int = {
            if let i = dict["duration"] as? Int { return i }
            if let d = dict["duration"] as? Double { return Int(d) }
            return 0
        }()
        let bitRate = dict["bitRate"] as? Int
        return SongHit(
            id: id,
            title: title,
            artist: artist,
            album: dict["album"] as? String,
            duration: duration,
            bitRate: bitRate,
            coverArt: dict["coverArt"] as? String,
            contentType: dict["contentType"] as? String,
            suffix: dict["suffix"] as? String
        )
    }

    private static func errorMessage(from json: [String: Any]) -> String? {
        if let err = json["error"] as? [String: Any] {
            if let m = err["message"] as? String { return m }
            if let c = err["code"] {
                return "错误码 \(c)"
            }
        }
        return nil
    }

    private func score(_ hit: SongHit, title: String, artist: String) -> Int {
        let t = normalize(title)
        let a = normalize(artist)
        let ht = normalize(hit.title)
        let ha = normalize(hit.artist)
        var s = 0
        if ht == t { s += 50 }
        else if ht.contains(t) || t.contains(ht) { s += 30 }
        if !a.isEmpty {
            if ha == a { s += 40 }
            else if ha.contains(a) || a.contains(ha) { s += 20 }
            for part in a.split(whereSeparator: { "/,、&".contains($0) }) {
                let p = normalize(String(part))
                if !p.isEmpty, ha.contains(p) { s += 10 }
            }
        }
        return s
    }

    private func scrub(_ raw: String) -> String {
        var s = raw
        for p in [#"\(.*?\)"#, #"（.*?）"#, #"\[.*?\]"#, #"【.*?】"#] {
            s = s.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        return s
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ s: String) -> String {
        scrub(s).lowercased()
    }

    private static func randomSalt(length: Int = 12) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
