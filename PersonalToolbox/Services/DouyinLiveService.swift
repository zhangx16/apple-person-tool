import Foundation

/// Douyin live APIs ported from SimpleLive `douyin_site.dart` v1.12.6.
actor DouyinLiveService {
    static let shared = DouyinLiveService()

    private let ua =
        "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400"
    private let defaultCookie =
        "ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511"
    private var cookie: String = ""

    /// Pull Cookie from Settings → 抖音直播 (user-supplied preferred over default).
    private func syncUserCookie() async {
        let user = await MainActor.run {
            AppSettings.shared.douyinLiveCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !user.isEmpty {
            cookie = user
        } else if cookie.isEmpty {
            cookie = defaultCookie
        }
    }

    private var effectiveCookie: String {
        let c = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? defaultCookie : c
    }

    // MARK: - Public

    func getCategories() async throws -> [LiveCategory] {
        // Static popular partitions (HTML scrape is brittle); IDs from SimpleLive homepage.
        let presets: [(String, String, String)] = [
            ("720,1", "推荐", "1"),
            ("2,1", "游戏", "1"),
            ("4,1", "娱乐", "1"),
            ("1,1", "聊天", "1"),
            ("9,1", "语音", "1"),
            ("6,1", "购物", "1")
        ]
        // Try scrape homepage for richer list
        if let scraped = try? await scrapeCategories(), !scraped.isEmpty {
            return scraped
        }
        return [
            LiveCategory(
                id: "root",
                name: "分区",
                children: presets.map {
                    LiveSubCategory(id: $0.0, name: $0.1, parentId: $0.2)
                }
            )
        ]
    }

    func getCategoryRooms(category: LiveSubCategory, page: Int = 1) async throws -> [LiveRoomItem] {
        let parts = category.id.split(separator: ",").map(String.init)
        let partition = parts.first ?? "720"
        let partitionType = parts.count > 1 ? parts[1] : "1"
        return try await roomsByPartition(partition: partition, type: partitionType, page: page)
    }

    func getRecommendRooms(page: Int = 1) async throws -> [LiveRoomItem] {
        try await roomsByPartition(partition: "720", type: "1", page: page)
    }

    private func roomsByPartition(partition: String, type: String, page: Int) async throws -> [LiveRoomItem] {
        let offset = (page - 1) * 15
        var comps = URLComponents(string: "https://live.douyin.com/webcast/web/partition/detail/room/v2/")!
        comps.queryItems = [
            URLQueryItem(name: "aid", value: "6383"),
            URLQueryItem(name: "app_name", value: "douyin_web"),
            URLQueryItem(name: "live_id", value: "1"),
            URLQueryItem(name: "device_platform", value: "web"),
            URLQueryItem(name: "language", value: "zh-CN"),
            URLQueryItem(name: "enter_from", value: "link_share"),
            URLQueryItem(name: "cookie_enabled", value: "true"),
            URLQueryItem(name: "screen_width", value: "1980"),
            URLQueryItem(name: "screen_height", value: "1080"),
            URLQueryItem(name: "browser_language", value: "zh-CN"),
            URLQueryItem(name: "browser_platform", value: "Win32"),
            URLQueryItem(name: "browser_name", value: "Edge"),
            URLQueryItem(name: "browser_version", value: "125.0.0.0"),
            URLQueryItem(name: "browser_online", value: "true"),
            URLQueryItem(name: "count", value: "15"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "partition", value: partition),
            URLQueryItem(name: "partition_type", value: type),
            URLQueryItem(name: "req_from", value: "2")
        ]
        guard let base = comps.url?.absoluteString else { throw NetworkError.invalidURL }
        let signed = try LiveJSEngine.shared.douyinAbogusURL(url: base, userAgent: ua)
        let json = try await getJSONURL(signed, headers: await requestHeaders())
        let rooms = resolveCategoryRooms(json)
        return rooms.compactMap { item in
            let webRid = LiveJSON.string(item["web_rid"])
            guard !webRid.isEmpty, let room = LiveJSON.object(item["room"]) else { return nil }
            let cover = urlListFirst(LiveJSON.object(room["cover"]))
            let owner = LiveJSON.object(room["owner"])
            let stats = LiveJSON.object(room["room_view_stats"])
            return LiveRoomItem(
                platform: .douyin,
                roomId: webRid,
                title: LiveJSON.string(room["title"]),
                cover: cover,
                userName: LiveJSON.string(owner?["nickname"]),
                online: LiveJSON.int(stats?["display_value"])
            )
        }
    }

    private func scrapeCategories() async throws -> [LiveCategory] {
        let html = try await getText(
            "https://live.douyin.com/",
            headers: await requestHeaders()
        )
        // Best-effort: look for categoryData JSON fragment
        guard let range = html.range(of: "categoryData") else { return [] }
        // Too fragile for full parse; return empty to use presets
        _ = range
        return []
    }

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        var comps = URLComponents(string: "https://www.douyin.com/aweme/v1/web/live/search/")!
        comps.queryItems = [
            URLQueryItem(name: "device_platform", value: "webapp"),
            URLQueryItem(name: "aid", value: "6383"),
            URLQueryItem(name: "channel", value: "channel_pc_web"),
            URLQueryItem(name: "search_channel", value: "aweme_live"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "search_source", value: "switch_tab"),
            URLQueryItem(name: "query_correct_type", value: "1"),
            URLQueryItem(name: "is_filter_search", value: "0"),
            URLQueryItem(name: "from_group_id", value: ""),
            URLQueryItem(name: "offset", value: "\((page - 1) * 10)"),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "pc_client_type", value: "1"),
            URLQueryItem(name: "version_code", value: "170400"),
            URLQueryItem(name: "version_name", value: "17.4.0"),
            URLQueryItem(name: "cookie_enabled", value: "true"),
            URLQueryItem(name: "screen_width", value: "1980"),
            URLQueryItem(name: "screen_height", value: "1080"),
            URLQueryItem(name: "browser_language", value: "zh-CN"),
            URLQueryItem(name: "browser_platform", value: "Win32"),
            URLQueryItem(name: "browser_name", value: "Edge"),
            URLQueryItem(name: "browser_version", value: "125.0.0.0"),
            URLQueryItem(name: "browser_online", value: "true"),
            URLQueryItem(name: "engine_name", value: "Blink"),
            URLQueryItem(name: "engine_version", value: "125.0.0.0"),
            URLQueryItem(name: "os_name", value: "Windows"),
            URLQueryItem(name: "os_version", value: "10"),
            URLQueryItem(name: "cpu_core_num", value: "12"),
            URLQueryItem(name: "device_memory", value: "8"),
            URLQueryItem(name: "platform", value: "PC"),
            URLQueryItem(name: "downlink", value: "10"),
            URLQueryItem(name: "effective_type", value: "4g"),
            URLQueryItem(name: "round_trip_time", value: "100"),
            URLQueryItem(name: "webid", value: "7382872326016435738")
        ]
        guard let url = comps.url?.absoluteString else { throw NetworkError.invalidURL }
        await syncUserCookie()
        var dyCookie = effectiveCookie
        if !dyCookie.hasSuffix(";") { dyCookie += ";" }
        // Refresh ttwid if possible
        if let refreshed = try? await headCookies(url: "https://live.douyin.com") {
            dyCookie = mergeCookie(dyCookie, refreshed)
        }
        let json = try await getJSONURL(url, headers: [
            "Authority": "www.douyin.com",
            "accept": "application/json, text/plain, */*",
            "cookie": dyCookie,
            "referer": "https://www.douyin.com/search/\(keyword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyword)?type=live",
            "user-agent": ua
        ])
        if LiveJSON.int(json["status_code"]) == 2483 {
            throw NetworkError.message("抖音搜索需要登录 Cookie，可稍后重试或用房间号打开")
        }
        let data = LiveJSON.array(json["data"]) ?? []
        return data.compactMap { item in
            guard let lives = LiveJSON.object(item["lives"]),
                  let raw = lives["rawdata"] as? String,
                  let rawData = raw.data(using: .utf8),
                  let itemData = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
                return nil
            }
            let owner = LiveJSON.object(itemData["owner"])
            let cover = urlListFirst(LiveJSON.object(itemData["cover"]))
            let avatar = urlListFirst(LiveJSON.object(owner?["avatar_thumb"]))
                .ifEmpty(urlListFirst(LiveJSON.object(owner?["avatar_medium"])))
                .ifEmpty(urlListFirst(LiveJSON.object(owner?["avatar_larger"])))
            let stats = LiveJSON.object(itemData["stats"])
            let webRid = LiveJSON.string(owner?["web_rid"])
            guard !webRid.isEmpty else { return nil }
            let partition = LiveJSON.object(itemData["partition"])
                ?? LiveJSON.object(itemData["partition_road_map"])
            var category = LiveJSON.string(partition?["title"])
            if category.isEmpty {
                category = LiveJSON.string(LiveJSON.object(itemData["category"])?["name"])
            }
            return LiveRoomItem(
                platform: .douyin,
                roomId: webRid,
                title: LiveJSON.string(itemData["title"]),
                cover: cover,
                userName: LiveJSON.string(owner?["nickname"]),
                online: LiveJSON.int(stats?["total_user"]),
                userAvatar: avatar,
                categoryName: category
            )
        }
    }

    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        if roomId.count <= 16 {
            return try await roomDetailByWebRid(roomId)
        }
        return try await roomDetailByRoomId(roomId)
    }

    func getPlayQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        let stream = LiveJSON.decodeObject(detail.playContextJSON)
        guard !stream.isEmpty else { return [] }
        var qualities: [LivePlayQuality] = []

        if let liveCore = LiveJSON.object(stream["live_core_sdk_data"]),
           let pull = LiveJSON.object(liveCore["pull_data"]),
           let options = LiveJSON.object(pull["options"]),
           let qList = LiveJSON.array(options["qualities"]) {
            let streamDataStr = LiveJSON.string(pull["stream_data"])
            if streamDataStr.hasPrefix("{"),
               let sd = streamDataStr.data(using: .utf8),
               let sdJSON = try? JSONSerialization.jsonObject(with: sd) as? [String: Any],
               let dataMap = LiveJSON.object(sdJSON["data"]) {
                for (idx, q) in qList.enumerated() {
                    let key = LiveJSON.string(q["sdk_key"])
                    var urls: [String] = []
                    if let main = LiveJSON.object(LiveJSON.object(dataMap[key])?["main"]) {
                        let flv = LiveJSON.string(main["flv"])
                        let hls = LiveJSON.string(main["hls"])
                        if !flv.isEmpty { urls.append(flv) }
                        if !hls.isEmpty { urls.append(hls) }
                    }
                    if !urls.isEmpty {
                        qualities.append(LivePlayQuality(
                            id: "dy-\(key)-\(idx)",
                            name: LiveJSON.string(q["name"]).isEmpty ? key : LiveJSON.string(q["name"]),
                            qn: LiveJSON.int(q["level"]),
                            readyURLs: urls
                        ))
                    }
                }
            } else {
                // Fallback flv_pull_url / hls_pull_url_map maps
                let flvMap = stream["flv_pull_url"] as? [String: Any] ?? [:]
                let hlsMap = stream["hls_pull_url_map"] as? [String: Any] ?? [:]
                let flvList = flvMap.values.compactMap { $0 as? String }
                let hlsList = hlsMap.values.compactMap { $0 as? String }
                for q in qList {
                    let level = LiveJSON.int(q["level"])
                    var urls: [String] = []
                    let fi = flvList.count - level
                    if fi >= 0, fi < flvList.count { urls.append(flvList[fi]) }
                    let hi = hlsList.count - level
                    if hi >= 0, hi < hlsList.count { urls.append(hlsList[hi]) }
                    if !urls.isEmpty {
                        qualities.append(LivePlayQuality(
                            id: "dy-lvl-\(level)",
                            name: LiveJSON.string(q["name"]),
                            qn: level,
                            readyURLs: urls
                        ))
                    }
                }
            }
        }

        if qualities.isEmpty {
            // Direct maps
            if let flv = stream["flv_pull_url"] as? [String: Any] {
                for (k, v) in flv {
                    if let s = v as? String, !s.isEmpty {
                        qualities.append(LivePlayQuality(id: "dy-flv-\(k)", name: "FLV \(k)", qn: 0, readyURLs: [s]))
                    }
                }
            }
            if let hls = stream["hls_pull_url_map"] as? [String: Any] {
                for (k, v) in hls {
                    if let s = v as? String, !s.isEmpty {
                        qualities.append(LivePlayQuality(id: "dy-hls-\(k)", name: "HLS \(k)", qn: 0, readyURLs: [s]))
                    }
                }
            }
        }

        qualities.sort { $0.qn > $1.qn }
        return qualities
    }

    func getPlayURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        guard !quality.readyURLs.isEmpty else { throw NetworkError.message("抖音无播放地址") }
        await syncUserCookie()
        return LivePlayResult(urls: quality.readyURLs, headers: [
            "User-Agent": ua,
            "Referer": "https://live.douyin.com/",
            "Cookie": effectiveCookie
        ])
    }

    // MARK: - Room detail paths

    private func roomDetailByWebRid(_ webRid: String) async throws -> LiveRoomDetail {
        if let d = try? await roomDetailByWebRidAPI(webRid) { return d }
        return try await roomDetailByWebRidHTML(webRid)
    }

    private func roomDetailByWebRidAPI(_ webRid: String) async throws -> LiveRoomDetail {
        var comps = URLComponents(string: "https://live.douyin.com/webcast/room/web/enter/")!
        comps.queryItems = [
            URLQueryItem(name: "aid", value: "6383"),
            URLQueryItem(name: "app_name", value: "douyin_web"),
            URLQueryItem(name: "live_id", value: "1"),
            URLQueryItem(name: "device_platform", value: "web"),
            URLQueryItem(name: "language", value: "zh-CN"),
            URLQueryItem(name: "browser_language", value: "zh-CN"),
            URLQueryItem(name: "browser_platform", value: "Win32"),
            URLQueryItem(name: "browser_name", value: "Chrome"),
            URLQueryItem(name: "browser_version", value: "125.0.0.0"),
            URLQueryItem(name: "web_rid", value: webRid),
            URLQueryItem(name: "msToken", value: "")
        ]
        guard let base = comps.url?.absoluteString else { throw NetworkError.invalidURL }
        let signed = try LiveJSEngine.shared.douyinAbogusURL(url: base, userAgent: ua)
        var headers = await requestHeaders()
        headers["Referer"] = "https://live.douyin.com/\(webRid)"
        let result = try await getJSONURL(signed, headers: headers)
        guard let data = LiveJSON.object(result["data"]),
              let rooms = LiveJSON.array(data["data"]),
              let roomData = rooms.first else {
            throw NetworkError.message("抖音直播间数据为空")
        }
        let userData = LiveJSON.object(data["user"]) ?? [:]
        let owner = LiveJSON.object(roomData["owner"]) ?? [:]
        let status = LiveJSON.int(roomData["status"])
        let isLive = status == 2
        let stream = isLive ? (LiveJSON.object(roomData["stream_url"]) ?? [:]) : [:]
        let cover = isLive ? urlListFirst(LiveJSON.object(roomData["cover"])) : ""
        let nick = isLive ? LiveJSON.string(owner["nickname"]) : LiveJSON.string(userData["nickname"])
        let avatar = isLive
            ? urlListFirst(LiveJSON.object(owner["avatar_thumb"]))
            : urlListFirst(LiveJSON.object(userData["avatar_thumb"]))
        let online = isLive ? LiveJSON.int(LiveJSON.object(roomData["room_view_stats"])?["display_value"]) : 0
        let numericRoomId = LiveJSON.string(roomData["id_str"]).ifEmpty(LiveJSON.string(roomData["id"]))
        let userUniqueId = randomDigits(12)
        let cookie = headers["cookie"] ?? headers["Cookie"] ?? defaultCookie
        return LiveRoomDetail(
            platform: .douyin,
            roomId: webRid,
            title: LiveJSON.string(roomData["title"]),
            cover: cover,
            userName: nick,
            userAvatar: avatar,
            online: online,
            isLive: isLive,
            webURL: "https://live.douyin.com/\(webRid)",
            introduction: LiveJSON.string(owner["signature"]),
            playContextJSON: LiveJSON.encode(stream),
            danmakuJSON: LiveJSON.encode([
                "webRid": webRid,
                "roomId": numericRoomId,
                "userId": userUniqueId,
                "cookie": cookie
            ])
        )
    }

    private func roomDetailByWebRidHTML(_ webRid: String) async throws -> LiveRoomDetail {
        let dyCookie = try await webCookie(webRid: webRid)
        let html = try await getText(
            "https://live.douyin.com/\(webRid)",
            headers: [
                "Authority": "live.douyin.com",
                "Referer": "https://live.douyin.com",
                "Cookie": dyCookie,
                "User-Agent": ua
            ]
        )
        guard html.contains("\\\"state\\\""),
              let re = try? NSRegularExpression(pattern: #"\{\\"state\\":\{\\"appStore[\s\S]*?\]\\n"#),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range, in: html) else {
            throw NetworkError.message("抖音页面解析失败（可能被风控）")
        }
        var str = String(html[r])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "]\\n", with: "")
        if str.hasSuffix("]\\n") { str = String(str.dropLast(3)) }
        guard let data = str.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = LiveJSON.object(root["state"]),
              let roomStore = LiveJSON.object(state["roomStore"]),
              let roomInfo = LiveJSON.object(roomStore["roomInfo"]),
              let room = LiveJSON.object(roomInfo["room"]) else {
            throw NetworkError.message("抖音页面状态解析失败")
        }
        let owner = LiveJSON.object(room["owner"]) ?? [:]
        let isLive = LiveJSON.int(room["status"]) == 2
        let stream = isLive ? (LiveJSON.object(room["stream_url"]) ?? [:]) : [:]
        let numericRoomId = LiveJSON.string(room["id_str"]).ifEmpty(LiveJSON.string(room["id"]))
        let userUniqueId = LiveJSON.string(
            LiveJSON.object(LiveJSON.object(state["userStore"])?["odin"])?["user_unique_id"]
        ).ifEmpty(randomDigits(12))
        return LiveRoomDetail(
            platform: .douyin,
            roomId: webRid,
            title: LiveJSON.string(room["title"]),
            cover: isLive ? urlListFirst(LiveJSON.object(room["cover"])) : "",
            userName: LiveJSON.string(owner["nickname"]),
            userAvatar: urlListFirst(LiveJSON.object(owner["avatar_thumb"])),
            online: isLive ? LiveJSON.int(LiveJSON.object(room["room_view_stats"])?["display_value"]) : 0,
            isLive: isLive,
            webURL: "https://live.douyin.com/\(webRid)",
            introduction: LiveJSON.string(owner["signature"]),
            playContextJSON: LiveJSON.encode(stream),
            danmakuJSON: LiveJSON.encode([
                "webRid": webRid,
                "roomId": numericRoomId,
                "userId": userUniqueId,
                "cookie": dyCookie
            ])
        )
    }

    private func roomDetailByRoomId(_ roomId: String) async throws -> LiveRoomDetail {
        let json = try await getJSONURL(
            "https://webcast.amemv.com/webcast/room/reflow/info/?type_id=0&live_id=1&room_id=\(roomId)&sec_user_id=&version_code=99.99.99&app_id=6383",
            headers: await requestHeaders()
        )
        guard let data = LiveJSON.object(json["data"]),
              let room = LiveJSON.object(data["room"]) else {
            throw NetworkError.message("抖音 roomId 查询失败")
        }
        let owner = LiveJSON.object(room["owner"]) ?? [:]
        let webRid = LiveJSON.string(owner["web_rid"])
        let status = LiveJSON.int(room["status"])
        if status == 4, !webRid.isEmpty {
            return try await roomDetailByWebRid(webRid)
        }
        let isLive = status == 2
        let stream = isLive ? (LiveJSON.object(room["stream_url"]) ?? [:]) : [:]
        let rid = webRid.isEmpty ? roomId : webRid
        let headers = await requestHeaders()
        let cookie = headers["cookie"] ?? headers["Cookie"] ?? defaultCookie
        return LiveRoomDetail(
            platform: .douyin,
            roomId: rid,
            title: LiveJSON.string(room["title"]),
            cover: isLive ? urlListFirst(LiveJSON.object(room["cover"])) : "",
            userName: LiveJSON.string(owner["nickname"]),
            userAvatar: urlListFirst(LiveJSON.object(owner["avatar_thumb"])),
            online: isLive ? LiveJSON.int(LiveJSON.object(room["room_view_stats"])?["display_value"]) : 0,
            isLive: isLive,
            webURL: "https://live.douyin.com/\(rid)",
            introduction: LiveJSON.string(owner["signature"]),
            playContextJSON: LiveJSON.encode(stream),
            danmakuJSON: LiveJSON.encode([
                "webRid": rid,
                "roomId": LiveJSON.string(room["id_str"]).ifEmpty(roomId),
                "userId": randomDigits(12),
                "cookie": cookie
            ])
        )
    }

    private func randomDigits(_ n: Int) -> String {
        String((0..<n).map { _ in String(Int.random(in: 0...9)) }.joined())
    }

    // MARK: - Helpers

    private func resolveCategoryRooms(_ json: [String: Any]) -> [[String: Any]] {
        if let data = LiveJSON.object(json["data"]) {
            if let list = LiveJSON.array(data["data"]) { return list }
            if let list = LiveJSON.array(data["list"]) { return list }
        }
        return LiveJSON.array(json["data"]) ?? []
    }

    private func requestHeaders() async -> [String: String] {
        await syncUserCookie()
        return [
            "Authority": "live.douyin.com",
            "Referer": "https://live.douyin.com",
            "User-Agent": ua,
            "cookie": effectiveCookie
        ]
    }

    private func webCookie(webRid: String) async throws -> String {
        await syncUserCookie()
        var base = effectiveCookie
        if let extra = try? await headCookies(url: "https://live.douyin.com/\(webRid)") {
            base = mergeCookie(base, extra)
        }
        cookie = base
        return base
    }

    private func headCookies(url: String) async throws -> String {
        await syncUserCookie()
        guard let u = URL(string: url) else { return "" }
        var req = URLRequest(url: u)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 10
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(effectiveCookie, forHTTPHeaderField: "Cookie")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return "" }
        var parts: [String] = []
        let headers = http.allHeaderFields
        for (k, v) in headers {
            if "\(k)".lowercased() == "set-cookie" {
                let c = "\(v)".split(separator: ";").first.map(String.init) ?? ""
                if c.contains("ttwid") || c.contains("__ac_nonce") {
                    parts.append(c)
                }
            }
        }
        // Also try getallheaderfields style
        if let cookies = HTTPCookieStorage.shared.cookies(for: u) {
            for c in cookies where c.name == "ttwid" || c.name == "__ac_nonce" {
                parts.append("\(c.name)=\(c.value)")
            }
        }
        return parts.joined(separator: "; ")
    }

    private func mergeCookie(_ base: String, _ extra: String) -> String {
        var map: [String: String] = [:]
        for part in (base + ";" + extra).split(separator: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            guard let eq = p.firstIndex(of: "=") else { continue }
            let k = String(p[..<eq])
            let v = String(p[p.index(after: eq)...])
            if !k.isEmpty { map[k] = v }
        }
        return map.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private func urlListFirst(_ map: [String: Any]?, key: String = "url_list") -> String {
        firstString(in: map?[key]) ?? ""
    }

    private func firstString(in any: Any?) -> String? {
        if let s = any as? String { return s }
        if let a = any as? [Any], let s = a.first as? String { return s }
        if let a = any as? [String], let s = a.first { return s }
        return nil
    }

    private func getJSONURL(_ url: String, headers: [String: String]) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: u)
        req.timeoutInterval = 25
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        if let s = String(data: data, encoding: .utf8), s == "blocked" || s.isEmpty {
            throw NetworkError.message("抖音接口被限制，请稍后再试")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("抖音 JSON 解析失败")
        }
        return obj
    }

    private func getText(_ url: String, headers: [String: String]) async throws -> String {
        guard let u = URL(string: url) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: u)
        req.timeoutInterval = 25
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}


private extension String {
    func ifEmpty(_ alt: String) -> String { isEmpty ? alt : self }
}
