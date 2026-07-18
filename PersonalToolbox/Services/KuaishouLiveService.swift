import Foundation

/// Kuaishou live — not in SimpleLive v1.12.6 core; ported from public mobile page approach
/// (real-url / m.gifshow.com) plus keyword/room-id entry.
actor KuaishouLiveService {
    static let shared = KuaishouLiveService()

    private let ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
    private let did = "web_d563dca728d28b00336877723e0359ed"

    // MARK: - Public

    /// No stable public recommend API without auth — return empty with guidance via search.
    func getRecommendRooms(page: Int = 1) async throws -> [LiveRoomItem] {
        // Try official reco feed (often needs cookie / geo); fall back to empty.
        if page == 1, let items = try? await recoFeed() , !items.isEmpty {
            return items
        }
        return []
    }

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }
        // Direct room id open: treat as principal id / short id
        if page == 1 {
            if let detail = try? await getRoomDetail(roomId: kw), detail.isLive || !detail.title.isEmpty {
                return [
                    LiveRoomItem(
                        platform: .kuaishou,
                        roomId: detail.roomId,
                        title: detail.title.isEmpty ? kw : detail.title,
                        cover: detail.cover,
                        userName: detail.userName.isEmpty ? kw : detail.userName,
                        online: detail.online
                    )
                ]
            }
        }
        // GraphQL / search is heavily gated; return empty with clear error if nothing
        if page == 1 {
            throw NetworkError.message("快手暂无公开搜索接口。请直接输入主播 ID / 直播间号（如 KPL704668133）")
        }
        return []
    }

    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prefer mobile fw page used by real-url
        if let d = try? await parseMobilePage(rid) { return d }
        // Desktop live page fallback
        if let d = try? await parseDesktopPage(rid) { return d }
        throw NetworkError.message("快手直播间不存在、未开播或需要 Cookie")
    }

    func getPlayQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        let ctx = LiveJSON.decodeObject(detail.playContextJSON)
        let quals = LiveJSON.array(ctx["qualities"]) ?? []
        if !quals.isEmpty {
            return quals.enumerated().map { idx, q in
                let urls: [String]
                if let arr = q["urls"] as? [String] {
                    urls = arr
                } else if let arr = q["urls"] as? [Any] {
                    urls = arr.map { LiveJSON.string($0) }.filter { !$0.isEmpty }
                } else {
                    urls = []
                }
                return LivePlayQuality(
                    id: "ks-\(idx)-\(LiveJSON.string(q["name"]))",
                    name: LiveJSON.string(q["name"]).isEmpty ? "线路\(idx + 1)" : LiveJSON.string(q["name"]),
                    qn: LiveJSON.int(q["level"]),
                    readyURLs: urls
                )
            }
        }
        let urls = (ctx["urls"] as? [String]) ?? []
        if urls.isEmpty { return [] }
        return [LivePlayQuality(id: "ks-default", name: "默认", qn: 0, readyURLs: urls)]
    }

    func getPlayURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        guard !quality.readyURLs.isEmpty else { throw NetworkError.message("快手无播放地址") }
        return LivePlayResult(urls: quality.readyURLs, headers: [
            "User-Agent": ua,
            "Referer": "https://live.kuaishou.com/",
            "Cookie": "did=\(did)"
        ])
    }

    // MARK: - Internals

    private func recoFeed() async throws -> [LiveRoomItem] {
        // Best-effort; may 404
        let url = "https://live.kuaishou.com/live_api/reco/feed?page=1"
        let json = try await getJSON(url)
        let list = LiveJSON.array(LiveJSON.object(json["data"])?["list"])
            ?? LiveJSON.array(json["data"])
            ?? []
        return list.compactMap { item in
            let author = LiveJSON.object(item["author"]) ?? LiveJSON.object(item["user"]) ?? item
            let roomId = LiveJSON.string(author["id"])
                .ifEmpty(LiveJSON.string(author["principalId"]))
                .ifEmpty(LiveJSON.string(item["userId"]))
            guard !roomId.isEmpty else { return nil }
            let cover = LiveJSON.string(item["coverUrl"])
                .ifEmpty(LiveJSON.string(LiveJSON.object(item["poster"])?["url"]))
                .ifEmpty(LiveJSON.string(item["poster"]))
            return LiveRoomItem(
                platform: .kuaishou,
                roomId: roomId,
                title: LiveJSON.string(item["caption"]).ifEmpty(LiveJSON.string(item["title"])),
                cover: cover,
                userName: LiveJSON.string(author["name"]).ifEmpty(LiveJSON.string(author["user_name"])),
                online: LiveJSON.int(item["displayWatchingCount"]).nonZero
                    ?? LiveJSON.int(item["watchingCount"])
            )
        }
    }

    private func parseMobilePage(_ rid: String) async throws -> LiveRoomDetail {
        let html = try await getText("https://m.gifshow.com/fw/live/\(rid)")
        // liveStream":{...},"obfuseData
        guard let re = try? NSRegularExpression(pattern: #"liveStream":(\{.*?\}),"obfuseData"#, options: .dotMatchesLineSeparators),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: html) else {
            // alternate pattern
            if let re2 = try? NSRegularExpression(pattern: #""liveStream":(\{[\s\S]*?\}),"#, options: []),
               let m2 = re2.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               m2.numberOfRanges > 1,
               let r2 = Range(m2.range(at: 1), in: html) {
                return try detailFromLiveStreamJSON(String(html[r2]), roomId: rid)
            }
            throw NetworkError.message("快手移动页无流信息")
        }
        return try detailFromLiveStreamJSON(String(html[r]), roomId: rid)
    }

    private func parseDesktopPage(_ rid: String) async throws -> LiveRoomDetail {
        let html = try await getText("https://live.kuaishou.com/u/\(rid)")
        // Try extract play urls from page
        if let re = try? NSRegularExpression(pattern: #""liveStream":(\{[\s\S]*?\}),"obfuseData""#),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: html) {
            return try detailFromLiveStreamJSON(String(html[r]), roomId: rid)
        }
        // Fallback: multiResolutionPlayUrls / hls
        var urls: [String] = []
        if let re = try? NSRegularExpression(pattern: #"https://[^"']+\.m3u8[^"']*"#) {
            let matches = re.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for m in matches.prefix(6) {
                if let rr = Range(m.range, in: html) {
                    let u = String(html[rr]).replacingOccurrences(of: "\\u002F", with: "/")
                    if !urls.contains(u) { urls.append(u) }
                }
            }
        }
        if urls.isEmpty { throw NetworkError.message("快手桌面页解析失败") }
        let title = firstMatch(html, #"liveStreamName":"([^"]+)""#)
            ?? firstMatch(html, #"caption":"([^"]+)""#)
            ?? rid
        let nick = firstMatch(html, #"user_name":"([^"]+)""#)
            ?? firstMatch(html, #"name":"([^"]+)""#)
            ?? rid
        return LiveRoomDetail(
            platform: .kuaishou,
            roomId: rid,
            title: title,
            cover: "",
            userName: nick,
            userAvatar: "",
            online: 0,
            isLive: true,
            webURL: "https://live.kuaishou.com/u/\(rid)",
            introduction: "",
            playContextJSON: LiveJSON.encode(["urls": urls])
        )
    }

    private func detailFromLiveStreamJSON(_ jsonText: String, roomId: String) throws -> LiveRoomDetail {
        guard let data = jsonText.data(using: .utf8),
              let stream = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("快手流 JSON 解析失败")
        }
        var qualities: [[String: Any]] = []
        // multiResolutionHlsPlayUrls
        if let multi = stream["multiResolutionHlsPlayUrls"] as? [Any] {
            for (idx, item) in multi.enumerated() {
                guard let map = item as? [String: Any] else { continue }
                let name = LiveJSON.string(map["type"]).ifEmpty(LiveJSON.string(map["name"])).ifEmpty("画质\(idx + 1)")
                let level = LiveJSON.int(map["level"]).nonZero ?? (100 - idx)
                var urls: [String] = []
                if let arr = map["urls"] as? [[String: Any]] {
                    for u in arr {
                        let url = LiveJSON.string(u["url"])
                        if !url.isEmpty { urls.append(url) }
                    }
                }
                if !urls.isEmpty {
                    qualities.append(["name": name, "level": level, "urls": urls])
                }
            }
        }
        // multiResolutionPlayUrls (flv)
        if qualities.isEmpty, let multi = stream["multiResolutionPlayUrls"] as? [Any] {
            for (idx, item) in multi.enumerated() {
                guard let map = item as? [String: Any] else { continue }
                let name = LiveJSON.string(map["type"]).ifEmpty("画质\(idx + 1)")
                var urls: [String] = []
                if let arr = map["urls"] as? [[String: Any]] {
                    for u in arr {
                        let url = LiveJSON.string(u["url"])
                        if !url.isEmpty { urls.append(url) }
                    }
                }
                if !urls.isEmpty {
                    qualities.append(["name": name, "level": 100 - idx, "urls": urls])
                }
            }
        }
        // playUrls
        if qualities.isEmpty, let playUrls = stream["playUrls"] as? [String: Any] {
            for (k, v) in playUrls {
                if let m = v as? [String: Any], let url = m["url"] as? String, !url.isEmpty {
                    qualities.append(["name": k, "level": 0, "urls": [url]])
                } else if let url = v as? String, !url.isEmpty {
                    qualities.append(["name": k, "level": 0, "urls": [url]])
                }
            }
        }

        let caption = LiveJSON.string(stream["caption"]).ifEmpty(LiveJSON.string(stream["liveStreamName"]))
        let nick = LiveJSON.string(LiveJSON.object(stream["user"])?["user_name"])
            .ifEmpty(LiveJSON.string(LiveJSON.object(stream["user"])?["name"]))
            .ifEmpty(roomId)
        let cover = LiveJSON.string(stream["coverUrl"])
            .ifEmpty(LiveJSON.string(LiveJSON.object(stream["poster"])?["url"]))
        let watching = LiveJSON.int(stream["displayWatchingCount"]).nonZero
            ?? LiveJSON.int(stream["watchingCount"])
        let isLive = !qualities.isEmpty || LiveJSON.int(stream["living"]) == 1
        return LiveRoomDetail(
            platform: .kuaishou,
            roomId: roomId,
            title: caption.isEmpty ? roomId : caption,
            cover: cover,
            userName: nick,
            userAvatar: LiveJSON.string(LiveJSON.object(stream["user"])?["headurl"]),
            online: watching,
            isLive: isLive,
            webURL: "https://live.kuaishou.com/u/\(roomId)",
            introduction: "",
            playContextJSON: LiveJSON.encode(["qualities": qualities])
        )
    }

    private func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private func getJSON(_ url: String) async throws -> [String: Any] {
        let text = try await getText(url)
        guard let data = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("快手 JSON 解析失败")
        }
        return obj
    }

    private func getText(_ url: String) async throws -> String {
        guard let u = URL(string: url) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: u)
        req.timeoutInterval = 25
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("did=\(did)", forHTTPHeaderField: "Cookie")
        req.setValue("https://live.kuaishou.com/", forHTTPHeaderField: "Referer")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension String {
    func ifEmpty(_ alt: String) -> String { isEmpty ? alt : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
