import Foundation

/// 快手直播 — 移植自 SimpleLive master `kuaishou_site.dart`（晚于 v1.12.6 合入）。
actor KuaishouLiveService {
    static let shared = KuaishouLiveService()

    private let ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private var cookie = ""
    private var cookieObj: [String: String] = [:]
    /// 用户设置的 Cookie（App 设置 → 快手直播）
    private var customCookie = ""
    private var customKww = ""
    private var bootstrapped = false
    /// roomId → playContextJSON 缓存（列表页常自带 playUrls，进房可秒开）
    private var playCache: [String: String] = [:]

    private static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "ico", "tif", "tiff"
    ]

    private func syncUserCredentials() async {
        let pair = await MainActor.run {
            (AppSettings.shared.kuaishouCookie, AppSettings.shared.kuaishouKww)
        }
        customCookie = pair.0.trimmingCharacters(in: .whitespacesAndNewlines)
        customKww = pair.1.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ensureSession() async {
        await syncUserCredentials()
        if !bootstrapped {
            bootstrapped = true
            // 先访问首页拿 did 等匿名 Cookie
            _ = try? await getText("https://live.kuaishou.com/", headers: baseHeaders)
            await harvestCookies(for: "https://live.kuaishou.com/")
            if cookieObj["did"] == nil || cookieObj["did"]?.isEmpty == true {
                let did = "web_" + String((0..<32).map { _ in "0123456789abcdef".randomElement()! })
                cookieObj["did"] = did
                cookie = formatCookieHeader(cookieObj)
            }
        }
        if !customCookie.isEmpty {
            cookieObj.merge(parseCookieHeader(customCookie)) { _, new in new }
            cookie = formatCookieHeader(cookieObj)
        }
    }

    // MARK: - Headers

    private var baseHeaders: [String: String] {
        [
            "User-Agent": ua,
            "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
            "connection": "keep-alive",
            "sec-ch-ua": "\"Google Chrome\";v=\"120\", \"Chromium\";v=\"120\", \"Not=A?Brand\";v=\"24\"",
            "sec-ch-ua-platform": "\"Windows\"",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-User": "?1"
        ]
    }

    private var headersWithCookie: [String: String] {
        var h = baseHeaders
        let c = currentCookieHeader()
        if !c.isEmpty { h["cookie"] = c }
        return h
    }

    private func searchHeaders(keyword: String) -> [String: String] {
        var h = headersWithCookie
        h["accept"] = "application/json, text/plain, */*"
        h["referer"] = "https://live.kuaishou.com/search?keyword=\(keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)"
        h["Sec-Fetch-Dest"] = "empty"
        h["Sec-Fetch-Mode"] = "cors"
        return h
    }

    // MARK: - Categories

    func getCategories() async throws -> [LiveCategory] {
        await ensureSession()
        let parents: [(String, String)] = [
            ("1", "热门"), ("2", "网游"), ("3", "单机"), ("4", "手游"),
            ("5", "棋牌"), ("6", "娱乐"), ("7", "综合"), ("8", "文化")
        ]
        var result: [LiveCategory] = []
        for (id, name) in parents {
            let subs = (try? await allSubCategories(parentId: id)) ?? []
            result.append(LiveCategory(id: id, name: name, children: subs))
        }
        return result
    }

    private func allSubCategories(parentId: String) async throws -> [LiveSubCategory] {
        var all: [LiveSubCategory] = []
        var page = 1
        let pageSize = 30
        while true {
            let batch = try await subCategories(parentId: parentId, page: page, size: pageSize)
            all.append(contentsOf: batch)
            if batch.count < pageSize { break }
            page += 1
            if page > 20 { break }
        }
        return all
    }

    private func subCategories(parentId: String, page: Int, size: Int) async throws -> [LiveSubCategory] {
        let json = try await getJSON(
            "https://live.kuaishou.com/live_api/category/data",
            query: ["type": parentId, "page": "\(page)", "size": "\(size)"],
            headers: baseHeaders
        )
        let list = LiveJSON.array(LiveJSON.object(json["data"])?["list"]) ?? []
        return list.map { item in
            LiveSubCategory(
                id: LiveJSON.string(item["id"]),
                name: LiveJSON.string(item["name"]),
                parentId: parentId,
                pic: LiveJSON.string(item["poster"])
            )
        }
    }

    func getCategoryRooms(category: LiveSubCategory, page: Int = 1) async throws -> [LiveRoomItem] {
        await ensureSession()
        let api = category.id.count < 7
            ? "https://live.kuaishou.com/live_api/gameboard/list"
            : "https://live.kuaishou.com/live_api/non-gameboard/list"
        let json = try await getJSON(
            api,
            query: [
                "filterType": "0",
                "pageSize": "20",
                "gameId": category.id,
                "page": "\(page)"
            ],
            headers: headersWithCookie
        )
        let list = LiveJSON.array(LiveJSON.object(json["data"])?["list"]) ?? []
        return list.compactMap { item in
            cachePlayURLsIfPresent(item)
            let author = LiveJSON.object(item["author"]) ?? [:]
            let roomId = LiveJSON.string(author["id"])
            guard !roomId.isEmpty else { return nil }
            var cover = LiveJSON.string(item["poster"])
            if !cover.isEmpty, !isImageURL(cover) { cover += ".jpg" }
            return LiveRoomItem(
                platform: .kuaishou,
                roomId: roomId,
                title: LiveJSON.string(item["caption"]).ifEmpty(LiveJSON.string(author["name"])),
                cover: cover,
                userName: LiveJSON.string(author["name"]),
                online: LiveJSON.int(item["watchingCount"])
            )
        }
    }

    // MARK: - Recommend

    func getRecommendRooms(page: Int = 1) async throws -> [LiveRoomItem] {
        await ensureSession()
        // Official home/list; page>1 often empty
        if page > 1 { return [] }
        // Prefer hot list (flat, includes playUrls)
        if let hot = try? await hotList(), !hot.isEmpty {
            return hot
        }
        let json = try await getJSON(
            "https://live.kuaishou.com/live_api/home/list",
            headers: headersWithCookie
        )
        let labels = LiveJSON.array(LiveJSON.object(json["data"])?["list"]) ?? []
        var items: [LiveRoomItem] = []
        for label in labels {
            for sitem in LiveJSON.array(label["gameLiveInfo"]) ?? [] {
                for titem in LiveJSON.array(sitem["liveInfo"]) ?? [] {
                    cachePlayURLsIfPresent(titem)
                    let author = LiveJSON.object(titem["author"]) ?? [:]
                    let gameInfo = LiveJSON.object(titem["gameInfo"]) ?? [:]
                    let roomId = LiveJSON.string(author["id"])
                    guard !roomId.isEmpty else { continue }
                    var cover = LiveJSON.string(titem["poster"])
                    if cover.isEmpty { cover = LiveJSON.string(gameInfo["poster"]) }
                    items.append(LiveRoomItem(
                        platform: .kuaishou,
                        roomId: roomId,
                        title: resolveRoomTitle(titem),
                        cover: cover,
                        userName: LiveJSON.string(author["name"]),
                        online: LiveJSON.int(titem["watchingCount"])
                    ))
                }
            }
        }
        if items.contains(where: { $0.online > 0 }) {
            items.sort { $0.online > $1.online }
        }
        return items
    }

    private func hotList() async throws -> [LiveRoomItem] {
        let json = try await getJSON(
            "https://live.kuaishou.com/live_api/hot/list?page=1",
            headers: headersWithCookie
        )
        let list = LiveJSON.array(LiveJSON.object(json["data"])?["list"]) ?? []
        return list.compactMap { live in
            cachePlayURLsIfPresent(live)
            let author = LiveJSON.object(live["author"]) ?? [:]
            let roomId = LiveJSON.string(author["id"]).ifEmpty(LiveJSON.string(live["id"]))
            guard !roomId.isEmpty else { return nil }
            return LiveRoomItem(
                platform: .kuaishou,
                roomId: roomId,
                title: LiveJSON.string(live["caption"]).ifEmpty(LiveJSON.string(live["id"])),
                cover: LiveJSON.string(live["poster"]),
                userName: LiveJSON.string(author["name"]).ifEmpty(roomId),
                online: LiveJSON.int(live["watchingCount"])
            )
        }
    }

    /// 把列表里的 playUrls（数组或 h264 字典）缓存为进房可用 playContext。
    private func cachePlayURLsIfPresent(_ item: [String: Any]) {
        let author = LiveJSON.object(item["author"]) ?? [:]
        let roomId = LiveJSON.string(author["id"]).ifEmpty(LiveJSON.string(item["id"]))
        guard !roomId.isEmpty else { return }
        if let ctx = encodePlayContext(from: item["playUrls"]) {
            playCache[roomId] = ctx
        }
    }

    private func encodePlayContext(from playUrls: Any?) -> String? {
        guard let playUrls else { return nil }
        // Dict form: { h264: { adaptationSet: ... } }
        if let map = playUrls as? [String: Any], !map.isEmpty {
            return LiveJSON.encode(map)
        }
        // Array form (gameboard/hot): [{ type, adaptationSet: { representation: [...] } }]
        if let arr = playUrls as? [Any], !arr.isEmpty {
            var qualities: [[String: Any]] = []
            for (idx, block) in arr.enumerated() {
                guard let map = block as? [String: Any] else { continue }
                if let adapt = LiveJSON.object(map["adaptationSet"]),
                   let reps = adapt["representation"] as? [[String: Any]] {
                    for rep in reps {
                        let url = LiveJSON.string(rep["url"])
                        guard !url.isEmpty else { continue }
                        qualities.append([
                            "name": LiveJSON.string(rep["name"]).ifEmpty(LiveJSON.string(rep["shortName"])).ifEmpty("画质"),
                            "level": LiveJSON.int(rep["level"]),
                            "urls": [url]
                        ])
                    }
                }
                if let urls = map["urls"] as? [[String: Any]] {
                    for u in urls {
                        let url = LiveJSON.string(u["url"])
                        if !url.isEmpty {
                            qualities.append(["name": "默认\(idx)", "level": 0, "urls": [url]])
                        }
                    }
                }
            }
            if !qualities.isEmpty {
                return LiveJSON.encode(["qualities": qualities])
            }
        }
        return nil
    }

    // MARK: - Search

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        await ensureSession()
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }
        if let direct = try? await searchLiveStreams(keyword: kw, page: page), !direct.isEmpty {
            return direct
        }
        if page > 1 { return [] }
        // overview fallback
        if let overview = try? await searchOverview(keyword: kw) {
            let streams = findOverviewSection(overview, type: "liveStreams")
            let items = streams.compactMap { parseSearchRoom($0) }
            if !items.isEmpty { return items }
        }
        // room id open
        if let detail = try? await getRoomDetail(roomId: kw), detail.isLive || !detail.title.isEmpty {
            return [
                LiveRoomItem(
                    platform: .kuaishou,
                    roomId: detail.roomId,
                    title: detail.title.isEmpty ? kw : detail.title,
                    cover: detail.cover,
                    userName: detail.userName.isEmpty ? kw : detail.userName,
                    online: detail.online,
                    userAvatar: detail.userAvatar
                )
            ]
        }
        return []
    }

    private func searchLiveStreams(keyword: String, page: Int) async throws -> [LiveRoomItem] {
        let json = try await getJSON(
            "https://live.kuaishou.com/live_api/search/liveStream",
            query: ["keyword": keyword, "page": "\(page)", "ussid": ""],
            headers: searchHeaders(keyword: keyword)
        )
        guard let data = LiveJSON.object(json["data"]), LiveJSON.int(data["result"]) == 1 else {
            return []
        }
        let list = LiveJSON.array(data["list"]) ?? []
        return list.compactMap { parseSearchRoom($0) }
    }

    private func searchOverview(keyword: String) async throws -> [String: Any] {
        let json = try await getJSON(
            "https://live.kuaishou.com/live_api/search/overview",
            query: ["keyword": keyword, "ussid": ""],
            headers: searchHeaders(keyword: keyword)
        )
        return LiveJSON.object(json["data"]) ?? [:]
    }

    private func findOverviewSection(_ overview: [String: Any], type: String) -> [[String: Any]] {
        let sections = LiveJSON.array(overview["list"]) ?? []
        for section in sections {
            if LiveJSON.string(section["type"]) == type {
                return LiveJSON.array(section["list"]) ?? []
            }
        }
        return []
    }

    private func parseSearchRoom(_ item: [String: Any]) -> LiveRoomItem? {
        let author = LiveJSON.object(item["author"]) ?? [:]
        let gameInfo = LiveJSON.object(item["gameInfo"]) ?? [:]
        let roomId = LiveJSON.string(author["id"])
            .ifEmpty(LiveJSON.string(item["authorId"]))
            .ifEmpty(LiveJSON.string(item["userId"]))
        guard !roomId.isEmpty else { return nil }
        var cover = LiveJSON.string(item["poster"])
            .ifEmpty(LiveJSON.string(item["coverUrl"]))
            .ifEmpty(LiveJSON.string(gameInfo["poster"]))
        if !cover.isEmpty, !isImageURL(cover) { cover += ".jpg" }
        var avatar = LiveJSON.string(author["headurl"])
            .ifEmpty(LiveJSON.string(author["avatar"]))
            .ifEmpty(LiveJSON.string(author["headUrl"]))
            .ifEmpty(LiveJSON.string(item["headurl"]))
        if !avatar.isEmpty, !isImageURL(avatar) { avatar += ".jpg" }
        var category = LiveJSON.string(gameInfo["name"])
            .ifEmpty(LiveJSON.string(gameInfo["categoryName"]))
            .ifEmpty(LiveJSON.string(item["categoryName"]))
        return LiveRoomItem(
            platform: .kuaishou,
            roomId: roomId,
            title: LiveJSON.string(item["caption"])
                .ifEmpty(LiveJSON.string(item["title"]))
                .ifEmpty(LiveJSON.string(author["name"])),
            cover: cover,
            userName: LiveJSON.string(author["name"]).ifEmpty(LiveJSON.string(item["userName"])),
            online: LiveJSON.int(item["watchingCount"]),
            userAvatar: avatar,
            categoryName: category
        )
    }

    // MARK: - Room detail

    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        await ensureSession()
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = "https://live.kuaishou.com/u/\(rid)"
        await refreshCookie(url: url)
        await registerDid()

        var pageDetail: LiveRoomDetail?
        if let withC = try? await loadRoomDetail(url: url, roomId: rid, withCookie: true) {
            pageDetail = withC
        } else if let anon = try? await loadRoomDetail(url: url, roomId: rid, withCookie: false) {
            pageDetail = anon
        }

        // 列表缓存的播放地址：页面解析失败或 play 为空时回退
        if let cached = playCache[rid], !cached.isEmpty {
            if var d = pageDetail {
                if d.playContextJSON == "{}" || d.playContextJSON.isEmpty {
                    d.playContextJSON = cached
                    d.isLive = true
                }
                return d
            }
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
                playContextJSON: cached,
                danmakuJSON: "{}"
            )
        }

        if let d = pageDetail { return d }
        if let m = try? await parseMobileFallback(rid) { return m }
        throw NetworkError.message("快手直播间不存在、未开播或需要 Cookie/登录")
    }

    private func loadRoomDetail(url: String, roomId: String, withCookie: Bool) async throws -> LiveRoomDetail {
        let html = try await getText(url, headers: withCookie ? headersWithCookie : baseHeaders)
        guard let detail = try await parseRoomDetail(html: html, roomId: roomId) else {
            throw NetworkError.message("快手页面解析失败")
        }
        return detail
    }

    private func parseRoomDetail(html: String, roomId: String) async throws -> LiveRoomDetail? {
        guard let re = try? NSRegularExpression(pattern: #"window\.__INITIAL_STATE__=(.*?);"#),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: html) else {
            return nil
        }
        var text = String(html[r]).replacingOccurrences(of: "undefined", with: "null")
        guard let data = text.data(using: .utf8),
              let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let liveroom = LiveJSON.object(jsonObj["liveroom"]),
              let playList = LiveJSON.array(liveroom["playList"]),
              let first = playList.first else {
            return nil
        }

        let liveStream = LiveJSON.object(first["liveStream"]) ?? [:]
        let author = LiveJSON.object(first["author"]) ?? [:]
        let gameInfo = LiveJSON.object(first["gameInfo"]) ?? [:]
        let isLiving = resolveLiveStatus(first)
        let liveStreamId = LiveJSON.string(liveStream["id"])
        var websocketUrls: [String] = []
        if let arr = liveroom["websocketUrls"] as? [Any] {
            websocketUrls = arr.map { LiveJSON.string($0) }.filter { !$0.isEmpty }
        }
        var danmakuToken = LiveJSON.string(liveroom["token"])
        let websocketInfo = LiveJSON.object(first["websocketInfo"]) ?? [:]
        if danmakuToken.isEmpty {
            danmakuToken = LiveJSON.string(websocketInfo["token"])
        }
        if websocketUrls.isEmpty {
            let extra = (websocketInfo["websocketUrls"] as? [Any])
                ?? (websocketInfo["webSocketAddresses"] as? [Any])
                ?? []
            websocketUrls = extra.map { LiveJSON.string($0) }.filter { !$0.isEmpty }
        }
        let authorId = LiveJSON.string(author["id"]).ifEmpty(roomId)
        if isLiving, !liveStreamId.isEmpty, (danmakuToken.isEmpty || websocketUrls.isEmpty) {
            let info = await fetchWebsocketInfo(roomId: authorId, liveStreamId: liveStreamId)
            if !info.token.isEmpty { danmakuToken = info.token }
            if websocketUrls.isEmpty { websocketUrls = info.urls }
        }

        var cover = LiveJSON.string(liveStream["poster"])
        if !cover.isEmpty, !isImageURL(cover) { cover += ".jpg" }

        // playUrls for qualities — keep full object as JSON
        let playUrls = liveStream["playUrls"] ?? [:]
        let playCtx: [String: Any]
        if let map = playUrls as? [String: Any] {
            playCtx = map
        } else {
            playCtx = ["raw": LiveJSON.string(playUrls)]
        }

        var category = LiveJSON.string(gameInfo["name"])
            .ifEmpty(LiveJSON.string(gameInfo["categoryName"]))
            .ifEmpty(LiveJSON.string(first["categoryName"]))
        return LiveRoomDetail(
            platform: .kuaishou,
            roomId: authorId,
            title: resolveRoomTitle(first),
            cover: cover,
            userName: LiveJSON.string(author["name"]),
            userAvatar: LiveJSON.string(author["avatar"]),
            online: isLiving ? LiveJSON.int(gameInfo["watchingCount"]) : 0,
            isLive: isLiving,
            webURL: "https://live.kuaishou.com/u/\(authorId)",
            introduction: LiveJSON.string(author["description"]),
            playContextJSON: LiveJSON.encode(playCtx),
            danmakuJSON: LiveJSON.encode([
                "roomId": authorId,
                "liveStreamId": liveStreamId,
                "token": danmakuToken,
                "websocketUrls": websocketUrls,
                "pageId": generatePageId(),
                "expTag": LiveJSON.string(liveStream["expTag"]),
                "attach": LiveJSON.string(first["expTag"]),
                "cookie": currentCookieHeader(),
                "userAgent": ua
            ]),
            categoryName: category
        )
    }

    private func fetchWebsocketInfo(roomId: String, liveStreamId: String) async -> (token: String, urls: [String]) {
        do {
            let kww = resolveServerKww(currentCookieHeader(), fallback: customKww)
            var headers = headersWithCookie
            headers["accept"] = "application/json, text/plain, */*"
            headers["referer"] = "https://live.kuaishou.com/u/\(roomId)"
            headers["Sec-Fetch-Dest"] = "empty"
            headers["Sec-Fetch-Mode"] = "cors"
            if !kww.isEmpty { headers["Kww"] = kww }
            let json = try await getJSON(
                "https://live.kuaishou.com/live_api/liveroom/websocketinfo",
                query: ["liveStreamId": liveStreamId],
                headers: headers
            )
            guard let data = LiveJSON.object(json["data"]) else { return ("", []) }
            let token = LiveJSON.string(data["token"])
            let arr = (data["websocketUrls"] as? [Any])
                ?? (data["webSocketAddresses"] as? [Any])
                ?? []
            let urls = arr.map { LiveJSON.string($0) }.filter { !$0.isEmpty }
            return (token, urls)
        } catch {
            return ("", [])
        }
    }

    // MARK: - Play

    func getPlayQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        var ctx = LiveJSON.decodeObject(detail.playContextJSON)
        if ctx.isEmpty, let cached = playCache[detail.roomId] {
            ctx = LiveJSON.decodeObject(cached)
        }
        var qualities: [LivePlayQuality] = []

        // Codec keys: h264 / hevc / freeTraffic...
        for (codecKey, codecVal) in ctx {
            if codecKey == "qualities" || codecKey == "urls" || codecKey == "raw" { continue }
            guard let codec = codecVal as? [String: Any],
                  let adapt = LiveJSON.object(codec["adaptationSet"]),
                  let reps = adapt["representation"] as? [[String: Any]] else { continue }
            for (idx, rep) in reps.enumerated() {
                let url = LiveJSON.string(rep["url"])
                guard !url.isEmpty else { continue }
                let name = LiveJSON.string(rep["name"]).ifEmpty(LiveJSON.string(rep["shortName"]))
                qualities.append(LivePlayQuality(
                    id: "ks-\(codecKey)-\(idx)",
                    name: name.isEmpty ? codecKey : "\(name)",
                    qn: LiveJSON.int(rep["level"]),
                    readyURLs: [url]
                ))
            }
        }

        // Cached qualities list
        if qualities.isEmpty, let quals = LiveJSON.array(ctx["qualities"]) {
            for (idx, q) in quals.enumerated() {
                let urls: [String]
                if let a = q["urls"] as? [String] { urls = a }
                else if let a = q["urls"] as? [Any] { urls = a.map { LiveJSON.string($0) }.filter { !$0.isEmpty } }
                else { urls = [] }
                if !urls.isEmpty {
                    qualities.append(LivePlayQuality(
                        id: "ks-q-\(idx)",
                        name: LiveJSON.string(q["name"]).ifEmpty("线路\(idx + 1)"),
                        qn: LiveJSON.int(q["level"]),
                        readyURLs: urls
                    ))
                }
            }
        }

        if qualities.isEmpty, let urls = ctx["urls"] as? [String], !urls.isEmpty {
            qualities = [LivePlayQuality(id: "ks-default", name: "默认", qn: 0, readyURLs: urls)]
        }

        // Prefer non-hevc first for AVPlayer compatibility, then by level
        qualities.sort { a, b in
            let aHevc = a.id.contains("hevc")
            let bHevc = b.id.contains("hevc")
            if aHevc != bHevc { return !aHevc && bHevc }
            return a.qn > b.qn
        }
        guard !qualities.isEmpty else {
            throw NetworkError.message("快手无可用清晰度")
        }
        return qualities
    }

    func getPlayURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        guard !quality.readyURLs.isEmpty else { throw NetworkError.message("快手无播放地址") }
        // Prefer HLS for iOS; keep others after.
        let sorted = quality.readyURLs.sorted { a, b in
            let am = a.contains(".m3u8") || a.contains("m3u8")
            let bm = b.contains(".m3u8") || b.contains("m3u8")
            if am != bm { return am && !bm }
            let aflv = a.contains(".flv")
            let bflv = b.contains(".flv")
            if aflv != bflv { return !aflv && bflv }
            return false
        }
        return LivePlayResult(urls: sorted, headers: [
            "User-Agent": ua,
            "Referer": "https://live.kuaishou.com/",
            "Cookie": currentCookieHeader()
        ])
    }

    // MARK: - Cookie / DID

    private func refreshCookie(url: String) async {
        do {
            guard let u = URL(string: url) else { return }
            var req = URLRequest(url: u)
            req.timeoutInterval = 20
            for (k, v) in headersWithCookie { req.setValue(v, forHTTPHeaderField: k) }
            _ = try await URLSession.shared.data(for: req)
            await harvestCookies(for: url)
        } catch {
            if cookieObj.isEmpty {
                cookieObj = parseCookieHeader(customCookie)
                cookie = formatCookieHeader(cookieObj)
            }
        }
    }

    private func harvestCookies(for urlString: String) async {
        var values = cookieObj
        values.merge(parseCookieHeader(customCookie)) { _, new in new }
        if let u = URL(string: urlString),
           let cookies = HTTPCookieStorage.shared.cookies(for: u) {
            for c in cookies { values[c.name] = c.value }
        }
        if let all = HTTPCookieStorage.shared.cookies {
            for c in all {
                let host = c.domain
                if host.contains("kuaishou") || host.contains("gifshow") || host.contains("ksapisrv") {
                    values[c.name] = c.value
                }
            }
        }
        if values["did"] == nil || values["did"]?.isEmpty == true {
            values["did"] = "web_" + String((0..<32).map { _ in "0123456789abcdef".randomElement()! })
        }
        cookieObj = values
        cookie = formatCookieHeader(values)
    }

    private func registerDid() async {
        let did = cookieObj["did"] ?? ""
        guard !did.isEmpty else { return }
        // Best-effort; ignore errors
        let body: [String: Any] = [
            "common": [
                "identity_package": ["device_id": did, "global_id": ""],
                "app_package": [
                    "language": "zh-CN",
                    "platform": 10,
                    "container": "WEB",
                    "product_name": "KS_GAME_LIVE_PC"
                ],
                "device_package": [
                    "os_version": "NT 10.0",
                    "model": "Windows",
                    "ua": ua
                ],
                "need_encrypt": "false",
                "network_package": ["type": 3],
                "h5_extra_attr":
                    "{\"sdk_name\":\"webLogger\",\"sdk_version\":\"3.9.49\",\"domain\":\"https://live.kuaishou.com\"}",
                "global_attr": "{}"
            ],
            "logs": [[
                "client_timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "session_id": uuidLike(),
                "event_package": ["task_event": ["type": 1, "status": 0]]
            ]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let u = URL(string: "https://log-sdk.ksapisrv.com/rest/wd/common/log/collect/misc2?v=3.9.49&kpn=KS_GAME_LIVE_PC") else {
            return
        }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Mobile fallback

    private func parseMobileFallback(_ rid: String) async throws -> LiveRoomDetail {
        let html = try await getText(
            "https://m.gifshow.com/fw/live/\(rid)",
            headers: [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15",
                "Cookie": currentCookieHeader().ifEmpty("did=web_d563dca728d28b00336877723e0359ed")
            ]
        )
        guard let re = try? NSRegularExpression(pattern: #"liveStream":(\{.*?\}),"obfuseData"#, options: .dotMatchesLineSeparators),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: html),
              let data = String(html[r]).data(using: .utf8),
              let stream = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("快手移动页无流信息")
        }
        var qualities: [[String: Any]] = []
        if let multi = stream["multiResolutionHlsPlayUrls"] as? [Any] {
            for (idx, item) in multi.enumerated() {
                guard let map = item as? [String: Any] else { continue }
                var urls: [String] = []
                if let arr = map["urls"] as? [[String: Any]] {
                    for u in arr {
                        let url = LiveJSON.string(u["url"])
                        if !url.isEmpty { urls.append(url) }
                    }
                }
                if !urls.isEmpty {
                    qualities.append([
                        "name": LiveJSON.string(map["type"]).ifEmpty("画质\(idx + 1)"),
                        "level": 100 - idx,
                        "urls": urls
                    ])
                }
            }
        }
        return LiveRoomDetail(
            platform: .kuaishou,
            roomId: rid,
            title: LiveJSON.string(stream["caption"]).ifEmpty(rid),
            cover: LiveJSON.string(stream["coverUrl"]),
            userName: LiveJSON.string(LiveJSON.object(stream["user"])?["user_name"]).ifEmpty(rid),
            userAvatar: "",
            online: LiveJSON.int(stream["watchingCount"]),
            isLive: !qualities.isEmpty,
            webURL: "https://live.kuaishou.com/u/\(rid)",
            introduction: "",
            playContextJSON: LiveJSON.encode(["qualities": qualities]),
            danmakuJSON: "{}"
        )
    }

    // MARK: - Helpers

    private func resolveRoomTitle(_ room: [String: Any]) -> String {
        let liveStream = LiveJSON.object(room["liveStream"]) ?? [:]
        let gameInfo = LiveJSON.object(room["gameInfo"]) ?? [:]
        let author = LiveJSON.object(room["author"]) ?? [:]
        for v in [
            room["caption"], room["title"],
            liveStream["caption"], liveStream["title"],
            gameInfo["name"], author["name"]
        ] {
            let t = LiveJSON.string(v).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return ""
    }

    private func resolveLiveStatus(_ room: [String: Any]) -> Bool {
        if isLiveFlag(room["isLiving"]) || isLiveFlag(room["living"]) { return true }
        let liveStream = LiveJSON.object(room["liveStream"]) ?? room
        let id = LiveJSON.string(liveStream["id"])
        return !id.isEmpty && containsPlayableURL(liveStream["playUrls"])
    }

    private func isLiveFlag(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if LiveJSON.int(v) == 1 { return true }
        return LiveJSON.string(v).lowercased() == "true"
    }

    private func containsPlayableURL(_ value: Any?) -> Bool {
        if let s = value as? String {
            let u = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return u.hasPrefix("http://") || u.hasPrefix("https://") || u.hasPrefix("rtmp://")
        }
        if let m = value as? [String: Any] {
            return m.values.contains { containsPlayableURL($0) }
        }
        if let a = value as? [Any] {
            return a.contains { containsPlayableURL($0) }
        }
        return false
    }

    private func isImageURL(_ url: String) -> Bool {
        let ext = (url as NSString).pathExtension.lowercased()
        return Self.imageExts.contains(ext)
    }

    private func currentCookieHeader() -> String {
        if !customCookie.isEmpty {
            return mergeCookie(customCookie, cookie)
        }
        return cookie
    }

    private func resolveServerKww(_ cookie: String, fallback: String) -> String {
        for part in cookie.split(separator: ";") {
            let item = part.trimmingCharacters(in: .whitespaces)
            guard item.hasPrefix("kwfv1=") else { continue }
            let value = String(item.dropFirst("kwfv1=".count)).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            let decoded = value.removingPercentEncoding ?? value
            return "\(decoded)###ssrc"
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseCookieHeader(_ cookie: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in cookie.split(separator: ";") {
            let item = part.trimmingCharacters(in: .whitespaces)
            guard let eq = item.firstIndex(of: "=") else { continue }
            let k = String(item[..<eq]).trimmingCharacters(in: .whitespaces)
            let v = String(item[item.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, !v.isEmpty { result[k] = v }
        }
        return result
    }

    private func formatCookieHeader(_ values: [String: String]) -> String {
        values.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private func mergeCookie(_ base: String, _ extra: String) -> String {
        var values = parseCookieHeader(base)
        values.merge(parseCookieHeader(extra)) { _, new in new }
        return formatCookieHeader(values)
    }

    private func generatePageId() -> String {
        let chars = Array("useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict")
        return String((0..<16).map { _ in chars.randomElement()! })
    }

    private func uuidLike() -> String {
        UUID().uuidString.lowercased()
    }

    private func getJSON(
        _ url: String,
        query: [String: String] = [:],
        headers: [String: String]
    ) async throws -> [String: Any] {
        let text = try await getText(url, query: query, headers: headers)
        guard let data = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("快手 JSON 解析失败")
        }
        return obj
    }

    private func getText(
        _ url: String,
        query: [String: String] = [:],
        headers: [String: String]
    ) async throws -> String {
        var comps = URLComponents(string: url)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let final = comps.url else { throw NetworkError.invalidURL }
        var req = URLRequest(url: final)
        req.timeoutInterval = 25
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
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
