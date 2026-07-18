import Foundation

/// Kuaishou live via `live.kuaishou.com/live_api` (home/hot list) + mobile page fallback.
actor KuaishouLiveService {
    static let shared = KuaishouLiveService()

    private let ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
    private let did = "web_d563dca728d28b00336877723e0359ed"
    private var homeListCache: [String: Any]?

    // MARK: - Public

    func getRecommendRooms(page: Int = 1) async throws -> [LiveRoomItem] {
        if page == 1 {
            if let hot = try? await hotList(), !hot.isEmpty { return hot }
        }
        let home = try await homeList()
        let labels = LiveJSON.array(LiveJSON.object(home["data"])?["list"]) ?? []
        var items: [LiveRoomItem] = []
        for label in labels {
            for game in LiveJSON.array(label["gameLiveInfo"]) ?? [] {
                for live in LiveJSON.array(game["liveInfo"]) ?? [] {
                    if let room = mapHomeLive(live) { items.append(room) }
                }
            }
        }
        // page is client-side slice (API often single page)
        let size = 30
        let start = (page - 1) * size
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + size, items.count)])
    }

    func getCategories() async throws -> [LiveCategory] {
        let home = try await homeList()
        let labels = LiveJSON.array(LiveJSON.object(home["data"])?["list"]) ?? []
        let children = labels.compactMap { label -> LiveSubCategory? in
            let id = LiveJSON.string(label["labelId"])
            let name = LiveJSON.string(label["labelName"])
            guard !id.isEmpty else { return nil }
            return LiveSubCategory(
                id: id,
                name: name.isEmpty ? "分类\(id)" : name,
                parentId: "ks",
                pic: LiveJSON.string(label["labelIcon"])
            )
        }
        return [LiveCategory(id: "ks", name: "快手", children: children)]
    }

    func getCategoryRooms(category: LiveSubCategory, page: Int = 1) async throws -> [LiveRoomItem] {
        let home = try await homeList()
        let labels = LiveJSON.array(LiveJSON.object(home["data"])?["list"]) ?? []
        var items: [LiveRoomItem] = []
        for label in labels {
            guard LiveJSON.string(label["labelId"]) == category.id else { continue }
            for game in LiveJSON.array(label["gameLiveInfo"]) ?? [] {
                for live in LiveJSON.array(game["liveInfo"]) ?? [] {
                    if let room = mapHomeLive(live) { items.append(room) }
                }
            }
        }
        let size = 30
        let start = (page - 1) * size
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + size, items.count)])
    }

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }
        // Filter recommend by keyword
        let all = (try? await getRecommendRooms(page: 1)) ?? []
        let filtered = all.filter {
            $0.userName.localizedCaseInsensitiveContains(kw)
                || $0.title.localizedCaseInsensitiveContains(kw)
                || $0.roomId.localizedCaseInsensitiveContains(kw)
        }
        if !filtered.isEmpty { return filtered }
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
            throw NetworkError.message("未找到「\(kw)」。可输入主播 ID，或从推荐/分类进入。")
        }
        return []
    }

    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prefer embedded play URLs from home/hot cache
        if let fromList = findInHomeCache(rid) {
            return fromList
        }
        if let d = try? await parseMobilePage(rid) { return d }
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

    // MARK: - Home / Hot APIs

    private func hotList() async throws -> [LiveRoomItem] {
        let json = try await getJSON("https://live.kuaishou.com/live_api/hot/list?page=1")
        let list = LiveJSON.array(LiveJSON.object(json["data"])?["list"]) ?? []
        return list.compactMap { mapHomeLive($0) }
    }

    private func homeList() async throws -> [String: Any] {
        if let homeListCache { return homeListCache }
        let json = try await getJSON("https://live.kuaishou.com/live_api/home/list?page=1")
        homeListCache = json
        return json
    }

    private func mapHomeLive(_ live: [String: Any]) -> LiveRoomItem? {
        let author = LiveJSON.object(live["author"]) ?? [:]
        let roomId = LiveJSON.string(author["id"])
            .ifEmpty(LiveJSON.string(live["id"]))
        guard !roomId.isEmpty else { return nil }
        return LiveRoomItem(
            platform: .kuaishou,
            roomId: roomId,
            title: LiveJSON.string(live["caption"]).ifEmpty(LiveJSON.string(live["id"])),
            cover: LiveJSON.string(live["poster"]),
            userName: LiveJSON.string(author["name"]).ifEmpty(roomId),
            online: LiveJSON.int(LiveJSON.object(author["counts"])?["fan"]) // may be 0
        )
    }

    private func findInHomeCache(_ rid: String) -> LiveRoomDetail? {
        guard let home = homeListCache else { return nil }
        let labels = LiveJSON.array(LiveJSON.object(home["data"])?["list"]) ?? []
        for label in labels {
            for game in LiveJSON.array(label["gameLiveInfo"]) ?? [] {
                for live in LiveJSON.array(game["liveInfo"]) ?? [] {
                    let author = LiveJSON.object(live["author"]) ?? [:]
                    let id = LiveJSON.string(author["id"]).ifEmpty(LiveJSON.string(live["id"]))
                    if id == rid || LiveJSON.string(live["id"]) == rid {
                        return detailFromHomeLive(live, roomId: id)
                    }
                }
            }
        }
        return nil
    }

    private func detailFromHomeLive(_ live: [String: Any], roomId: String) -> LiveRoomDetail {
        let author = LiveJSON.object(live["author"]) ?? [:]
        var qualities: [[String: Any]] = []
        // playUrls structure: [{type, adaptationSet: {representation: [{name,url,level}]}}]
        if let playUrls = live["playUrls"] as? [Any] {
            for block in playUrls {
                guard let map = block as? [String: Any] else { continue }
                if let adapt = LiveJSON.object(map["adaptationSet"]),
                   let reps = adapt["representation"] as? [[String: Any]] {
                    for rep in reps {
                        let url = LiveJSON.string(rep["url"])
                        guard !url.isEmpty else { continue }
                        qualities.append([
                            "name": LiveJSON.string(rep["name"]).ifEmpty(LiveJSON.string(rep["shortName"])).ifEmpty("默认"),
                            "level": LiveJSON.int(rep["level"]),
                            "urls": [url]
                        ])
                    }
                }
                if let arr = map["urls"] as? [[String: Any]] {
                    for u in arr {
                        let url = LiveJSON.string(u["url"])
                        if !url.isEmpty {
                            qualities.append(["name": "默认", "level": 0, "urls": [url]])
                        }
                    }
                }
            }
        }
        qualities.sort { LiveJSON.int($0["level"]) > LiveJSON.int($1["level"]) }
        return LiveRoomDetail(
            platform: .kuaishou,
            roomId: roomId,
            title: LiveJSON.string(live["caption"]),
            cover: LiveJSON.string(live["poster"]),
            userName: LiveJSON.string(author["name"]),
            userAvatar: LiveJSON.string(author["avatar"]),
            online: 0,
            isLive: !qualities.isEmpty || LiveJSON.int(author["living"]) == 1,
            webURL: "https://live.kuaishou.com/u/\(roomId)",
            introduction: LiveJSON.string(author["description"]),
            playContextJSON: LiveJSON.encode(["qualities": qualities])
        )
    }

    // MARK: - Page parse fallbacks

    private func parseMobilePage(_ rid: String) async throws -> LiveRoomDetail {
        let html = try await getText("https://m.gifshow.com/fw/live/\(rid)")
        if let re = try? NSRegularExpression(pattern: #"liveStream":(\{.*?\}),"obfuseData"#, options: .dotMatchesLineSeparators),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: html) {
            return try detailFromLiveStreamJSON(String(html[r]), roomId: rid)
        }
        throw NetworkError.message("快手移动页无流信息")
    }

    private func parseDesktopPage(_ rid: String) async throws -> LiveRoomDetail {
        let html = try await getText("https://live.kuaishou.com/u/\(rid)")
        var urls: [String] = []
        if let re = try? NSRegularExpression(pattern: #"https://[^"']+\.m3u8[^"']*"#) {
            for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)).prefix(6) {
                if let rr = Range(m.range, in: html) {
                    let u = String(html[rr]).replacingOccurrences(of: "\\u002F", with: "/")
                    if !urls.contains(u) { urls.append(u) }
                }
            }
        }
        if urls.isEmpty { throw NetworkError.message("快手桌面页解析失败") }
        return LiveRoomDetail(
            platform: .kuaishou,
            roomId: rid,
            title: rid,
            cover: "",
            userName: rid,
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
        if let multi = stream["multiResolutionHlsPlayUrls"] as? [Any] {
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
        let nick = LiveJSON.string(LiveJSON.object(stream["user"])?["user_name"])
            .ifEmpty(LiveJSON.string(LiveJSON.object(stream["user"])?["name"]))
            .ifEmpty(roomId)
        return LiveRoomDetail(
            platform: .kuaishou,
            roomId: roomId,
            title: LiveJSON.string(stream["caption"]).ifEmpty(roomId),
            cover: LiveJSON.string(stream["coverUrl"]),
            userName: nick,
            userAvatar: "",
            online: LiveJSON.int(stream["watchingCount"]),
            isLive: !qualities.isEmpty,
            webURL: "https://live.kuaishou.com/u/\(roomId)",
            introduction: "",
            playContextJSON: LiveJSON.encode(["qualities": qualities])
        )
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
