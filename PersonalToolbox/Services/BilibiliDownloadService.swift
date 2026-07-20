import Foundation

/// 本机 B 站视频下载 · 接口思路参考 nICEnnnnnnnLee/BilibiliDown（view + playurl）。
/// 优先 `fnval=1` 单文件流，避免 iOS 上 dash 音视频分离需 ffmpeg。
@MainActor
final class BilibiliDownloadService {
    static let shared = BilibiliDownloadService()

    private let ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"

    private init() {}

    var rootDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bilibili-downloader", isDirectory: true)
    }

    var videosDirectory: URL {
        rootDirectory.appendingPathComponent("videos", isDirectory: true)
    }

    func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
    }

    func listLocalFiles() -> [YTFileItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: videosDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
            return YTFileItem(id: "local:\(url.path)", name: url.lastPathComponent, size: size, path: url.path)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Detection

    nonisolated static func isBilibiliURL(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.contains("bilibili.com")
            || s.contains("b23.tv")
            || s.contains("bili2233.cn")
            || s.hasPrefix("bv")
            || s.hasPrefix("av")
            || s.contains("哔哩")
    }

    nonisolated static func extractURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http") {
            return trimmed.components(separatedBy: .whitespacesAndNewlines).first
        }
        if let bv = extractBVID(from: trimmed) { return "https://www.bilibili.com/video/\(bv)" }
        if let av = extractAID(from: trimmed) { return "https://www.bilibili.com/video/av\(av)" }
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let r = Range(match.range, in: trimmed) else { return nil }
        var url = String(trimmed[r])
        while let last = url.last, ".,);]》」』".contains(last) { url.removeLast() }
        return url
    }

    nonisolated static func extractBVID(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"BV[0-9A-Za-z]+"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = regex.firstMatch(in: text, range: range),
              let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    nonisolated static func extractAID(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:av|AV)(\d+)"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private var userCookie: String {
        AppSettings.shared.bilibiliCookie.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Public API

    struct PageInfo: Identifiable, Hashable {
        var id: Int { cid }
        var cid: Int
        var page: Int
        var part: String
        var duration: Int
    }

    struct VideoInfo: Hashable {
        var bvid: String
        var aid: Int
        var title: String
        var owner: String
        var cover: String
        var pages: [PageInfo]
    }

    struct DownloadResult: Hashable {
        var title: String
        var fileName: String
        var filePath: String
        var bvid: String
        var qualityLabel: String
        var bytes: Int64
        var thumbnailURL: String?
    }

    func parseMetadata(sourceURL: String, onLog: ((String) -> Void)? = nil) async throws -> (VideoMetadata, VideoInfo) {
        let info = try await resolveVideoInfo(sourceURL: sourceURL, onLog: onLog)
        let meta = VideoMetadata(
            title: info.title,
            duration: info.pages.first.map { "\($0.duration)s" },
            thumbnail: info.cover.isEmpty ? nil : info.cover,
            uploader: info.owner.isEmpty ? nil : info.owner
        )
        return (meta, info)
    }

    func download(
        sourceURL: String,
        pageIndex: Int = 0,
        qn: Int = 80,
        onProgress: ((Double, String) -> Void)? = nil,
        onLog: ((String) -> Void)? = nil
    ) async throws -> DownloadResult {
        onProgress?(0.05, "解析稿件信息…")
        let info = try await resolveVideoInfo(sourceURL: sourceURL, onLog: onLog)
        guard !info.pages.isEmpty else { throw NetworkError.message("无分 P 信息") }
        let page = info.pages[min(max(0, pageIndex), info.pages.count - 1)]
        onLog?("下载 \(info.bvid) P\(page.page)：\(page.part.isEmpty ? info.title : page.part)")

        onProgress?(0.15, "获取播放地址 qn=\(qn)…")
        let play = try await fetchPlayURL(bvid: info.bvid, cid: page.cid, qn: qn)
        guard let streamURL = play.url, let url = URL(string: streamURL) else {
            throw NetworkError.message("未获取到可下载地址（可能需登录 Cookie）")
        }
        onLog?("线路：\(play.qualityLabel) · \(play.format)")

        try ensureDirectories()
        onProgress?(0.25, "开始下载…")
        let partName = page.part.isEmpty ? info.title : "\(info.title)_P\(page.page)_\(page.part)"
        let fileName = sanitize("\(partName)_\(info.bvid).mp4")
        let dest = uniqueURL(in: videosDirectory, name: fileName)

        var req = URLRequest(url: url)
        req.timeoutInterval = 300
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        if !userCookie.isEmpty {
            req.setValue(userCookie, forHTTPHeaderField: "Cookie")
        }

        let (temp, response) = try await URLSession.shared.download(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.message("下载失败 HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: temp, to: dest)
        let bytes = Int64((try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard bytes > 10_000 else {
            try? FileManager.default.removeItem(at: dest)
            throw NetworkError.message("文件过小，可能被风控或 Cookie 无效")
        }
        onProgress?(1, "完成")
        onLog?("已保存 \(dest.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))")

        return DownloadResult(
            title: info.title,
            fileName: dest.lastPathComponent,
            filePath: dest.path,
            bvid: info.bvid,
            qualityLabel: play.qualityLabel,
            bytes: bytes,
            thumbnailURL: info.cover.isEmpty ? nil : info.cover
        )
    }

    // MARK: - Resolve

    private func resolveVideoInfo(sourceURL: String, onLog: ((String) -> Void)?) async throws -> VideoInfo {
        var url = Self.extractURL(from: sourceURL) ?? sourceURL
        if url.lowercased().contains("b23.tv") || url.lowercased().contains("bili2233.cn") {
            onLog?("展开短链…")
            url = await expandShortLink(url)
            onLog?("→ \(url)")
        }

        var bvid = Self.extractBVID(from: url)
        var aid = Self.extractAID(from: url).flatMap { Int($0) }

        if bvid == nil, let aid {
            // aid → view API also accepts aid=
            onLog?("使用 av\(aid) 查询…")
        } else if let b = bvid {
            onLog?("查询 \(b)…")
        } else {
            throw NetworkError.message("无法识别 BV/av 号，请粘贴完整视频链接")
        }

        var comps = URLComponents(string: "https://api.bilibili.com/x/web-interface/view")!
        if let bvid {
            comps.queryItems = [URLQueryItem(name: "bvid", value: bvid)]
        } else if let aid {
            comps.queryItems = [URLQueryItem(name: "aid", value: "\(aid)")]
        }
        let json = try await getJSON(comps.url!)
        guard int(json, "code") == 0, let data = json["data"] as? [String: Any] else {
            let msg = string(json, "message") ?? "稿件查询失败"
            throw NetworkError.message(msg)
        }

        let title = string(data, "title") ?? "B站视频"
        let owner = (data["owner"] as? [String: Any]).flatMap { string($0, "name") } ?? ""
        let cover = string(data, "pic") ?? ""
        let resolvedBvid = string(data, "bvid") ?? bvid ?? ""
        let resolvedAid = int(data, "aid") ?? aid ?? 0

        var pages: [PageInfo] = []
        if let arr = data["pages"] as? [[String: Any]] {
            for p in arr {
                pages.append(PageInfo(
                    cid: int(p, "cid") ?? 0,
                    page: int(p, "page") ?? (pages.count + 1),
                    part: string(p, "part") ?? "",
                    duration: int(p, "duration") ?? 0
                ))
            }
        }
        if pages.isEmpty, let cid = int(data, "cid") {
            pages = [PageInfo(cid: cid, page: 1, part: title, duration: int(data, "duration") ?? 0)]
        }
        pages = pages.filter { $0.cid > 0 }
        guard !resolvedBvid.isEmpty, !pages.isEmpty else {
            throw NetworkError.message("稿件信息不完整")
        }
        return VideoInfo(
            bvid: resolvedBvid,
            aid: resolvedAid,
            title: title,
            owner: owner,
            cover: cover.hasPrefix("//") ? "https:" + cover : cover,
            pages: pages
        )
    }

    private struct PlayInfo {
        var url: String?
        var qualityLabel: String
        var format: String
    }

    private func fetchPlayURL(bvid: String, cid: Int, qn: Int) async throws -> PlayInfo {
        // Prefer single-file progressive (fnval=1) — BilibiliDown also falls back to flv/mp4 when needed.
        let qns = [qn, 80, 64, 32, 16]
        var lastErr = "无地址"
        for tryQn in qns {
            for fnval in [1, 0] {
                var comps = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
                comps.queryItems = [
                    URLQueryItem(name: "bvid", value: bvid),
                    URLQueryItem(name: "cid", value: "\(cid)"),
                    URLQueryItem(name: "qn", value: "\(tryQn)"),
                    URLQueryItem(name: "fnver", value: "0"),
                    URLQueryItem(name: "fnval", value: "\(fnval)"),
                    URLQueryItem(name: "fourk", value: "1"),
                    URLQueryItem(name: "otype", value: "json")
                ]
                guard let url = comps.url else { continue }
                do {
                    let json = try await getJSON(url)
                    guard int(json, "code") == 0 else {
                        lastErr = string(json, "message") ?? "playurl \(int(json, "code") ?? -1)"
                        continue
                    }
                    let data = json["data"] as? [String: Any] ?? [:]
                    if let durl = data["durl"] as? [[String: Any]], let first = durl.first {
                        var stream = string(first, "url")
                        if stream == nil, let backups = first["backup_url"] as? [Any] {
                            stream = backups.compactMap { $0 as? String }.first
                        }
                        if let stream {
                            let qnLabel = qualityName(tryQn, accept: data["accept_description"] as? [String])
                            return PlayInfo(url: stream, qualityLabel: qnLabel, format: "durl/fnval=\(fnval)")
                        }
                    }
                    // dash fallback: pick highest video only (silent) is bad; try audio+video note
                    if let dash = data["dash"] as? [String: Any],
                       let videos = dash["video"] as? [[String: Any]],
                       let best = videos.max(by: { (int($0, "bandwidth") ?? 0) < (int($1, "bandwidth") ?? 0) }),
                       let base = string(best, "baseUrl") ?? string(best, "base_url") {
                        // Prefer if there's a single mixed isn't available — still return video track
                        // with label so user knows; many phones can play video-only mp4/m4s poorly.
                        // Skip dash-only for now if we can keep trying lower qn single file.
                        lastErr = "仅 dash 分轨（需合并），尝试其它清晰度"
                        // Store as last resort after loop
                        if tryQn == qns.last, fnval == 0 {
                            let qnLabel = qualityName(int(best, "id") ?? tryQn, accept: nil)
                            return PlayInfo(url: base, qualityLabel: "\(qnLabel)·视频轨", format: "dash-video")
                        }
                        continue
                    }
                } catch {
                    lastErr = error.localizedDescription
                }
            }
        }
        throw NetworkError.message(lastErr)
    }

    private func qualityName(_ qn: Int, accept: [String]?) -> String {
        let map: [Int: String] = [
            127: "8K", 126: "杜比视界", 125: "HDR", 120: "4K",
            116: "1080P60", 112: "1080P+", 80: "1080P", 74: "720P60",
            64: "720P", 32: "480P", 16: "360P"
        ]
        return map[qn] ?? "qn\(qn)"
    }

    // MARK: - HTTP

    private func expandShortLink(_ raw: String) async -> String {
        guard let start = URL(string: raw) else { return raw }
        var req = URLRequest(url: start)
        req.httpMethod = "GET"
        req.timeoutInterval = 12
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: BiliRedirectCapture(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse,
               let loc = http.value(forHTTPHeaderField: "Location"), loc.hasPrefix("http") {
                return loc
            }
            if let final = resp.url?.absoluteString, final.hasPrefix("http") { return final }
        } catch {}
        return raw
    }

    private func getJSON(_ url: URL) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if !userCookie.isEmpty {
            req.setValue(userCookie, forHTTPHeaderField: "Cookie")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.message("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("JSON 解析失败")
        }
        return obj
    }

    private func string(_ obj: [String: Any], _ key: String) -> String? {
        if let s = obj[key] as? String { return s }
        if let n = obj[key] as? NSNumber { return n.stringValue }
        if let a = obj[key] as? [Any], let s = a.first as? String { return s }
        return nil
    }

    private func int(_ obj: [String: Any], _ key: String) -> Int? {
        if let i = obj[key] as? Int { return i }
        if let n = obj[key] as? NSNumber { return n.intValue }
        if let s = obj[key] as? String { return Int(s) }
        return nil
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "bilibili_video" : String(trimmed.prefix(80))
    }

    private func uniqueURL(in dir: URL, name: String) -> URL {
        var candidate = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let n = ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)"
            candidate = dir.appendingPathComponent(n)
            i += 1
        }
        return candidate
    }
}

private final class BiliRedirectCapture: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
