import Foundation

/// Douyu live APIs ported from SimpleLive `douyu_site.dart` v1.12.6.
/// Play sign uses JavaScriptCore + CryptoJS (same as SimpleLive QuickJS path).
actor DouyuLiveService {
    static let shared = DouyuLiveService()

    private let ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43"

    // MARK: - Public

    func getCategories() async throws -> [LiveCategory] {
        let json = try await getJSON("https://m.douyu.com/api/cate/list")
        guard let data = LiveJSON.object(json["data"]) else { return [] }
        let cate1 = LiveJSON.array(data["cate1Info"]) ?? []
        let cate2 = LiveJSON.array(data["cate2Info"]) ?? []
        return cate1.compactMap { item -> LiveCategory? in
            let id = LiveJSON.string(item["cate1Id"])
            guard !id.isEmpty else { return nil }
            let subs = cate2.compactMap { sub -> LiveSubCategory? in
                guard LiveJSON.string(sub["cate1Id"]) == id else { return nil }
                return LiveSubCategory(
                    id: LiveJSON.string(sub["cate2Id"]),
                    name: LiveJSON.string(sub["cate2Name"]),
                    parentId: id,
                    pic: LiveJSON.string(sub["icon"])
                )
            }
            return LiveCategory(id: id, name: LiveJSON.string(item["cate1Name"]), children: subs)
        }.sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
    }

    func getCategoryRooms(category: LiveSubCategory, page: Int = 1) async throws -> [LiveRoomItem] {
        let json = try await getJSON(
            "https://www.douyu.com/gapi/rkc/directory/mixList/2_\(category.id)/\(page)"
        )
        let rl = LiveJSON.array(LiveJSON.object(json["data"])?["rl"]) ?? []
        return rl.compactMap { item in
            guard LiveJSON.int(item["type"]) == 1 else { return nil }
            return LiveRoomItem(
                platform: .douyu,
                roomId: LiveJSON.string(item["rid"]),
                title: LiveJSON.string(item["rn"]),
                cover: LiveJSON.string(item["rs16"]),
                userName: LiveJSON.string(item["nn"]),
                online: LiveJSON.int(item["ol"])
            )
        }
    }

    func getRecommendRooms(page: Int = 1) async throws -> [LiveRoomItem] {
        let json = try await getJSON("https://www.douyu.com/japi/weblist/apinc/allpage/6/\(page)")
        let rl = LiveJSON.array(LiveJSON.object(json["data"])?["rl"]) ?? []
        return rl.compactMap { item in
            guard LiveJSON.int(item["type"]) == 1 else { return nil }
            return LiveRoomItem(
                platform: .douyu,
                roomId: LiveJSON.string(item["rid"]),
                title: LiveJSON.string(item["rn"]),
                cover: LiveJSON.string(item["rs16"]),
                userName: LiveJSON.string(item["nn"]),
                online: LiveJSON.int(item["ol"])
            )
        }
    }

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        let did = randomHex(32)
        let json = try await getJSON(
            "https://www.douyu.com/japi/search/api/searchShow",
            query: ["kw": keyword, "page": "\(page)", "pageSize": "20"],
            headers: [
                "User-Agent": ua,
                "Referer": "https://www.douyu.com/search/",
                "Cookie": "dy_did=\(did);acf_did=\(did)"
            ]
        )
        if LiveJSON.int(json["error"]) != 0 {
            throw NetworkError.message(LiveJSON.string(json["msg"]).isEmpty ? "斗鱼搜索失败" : LiveJSON.string(json["msg"]))
        }
        let list = LiveJSON.array(LiveJSON.object(json["data"])?["relateShow"]) ?? []
        return list.map { item in
            LiveRoomItem(
                platform: .douyu,
                roomId: LiveJSON.string(item["rid"]),
                title: LiveJSON.string(item["roomName"]),
                cover: LiveJSON.string(item["roomSrc"]),
                userName: LiveJSON.string(item["nickName"]),
                online: parseHot(LiveJSON.string(item["hot"]))
            )
        }
    }

    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        let room = try await getRoomInfo(roomId)
        let rid = LiveJSON.string(room["room_id"]).isEmpty ? roomId : LiveJSON.string(room["room_id"])
        let encText = try await getText(
            "https://www.douyu.com/swf_api/homeH5Enc?rids=\(rid)",
            headers: [
                "Referer": "https://www.douyu.com/\(rid)",
                "User-Agent": ua
            ]
        )
        guard let encData = encText.data(using: .utf8),
              let encJSON = try JSONSerialization.jsonObject(with: encData) as? [String: Any],
              let crptext = LiveJSON.object(encJSON["data"])?["room\(rid)"] as? String else {
            throw NetworkError.message("斗鱼签名脚本获取失败")
        }
        let sign = try LiveJSEngine.shared.douyuSign(encryptedJS: crptext, roomId: rid)
        let isLive = LiveJSON.int(room["show_status"]) == 1 && LiveJSON.int(room["videoLoop"]) != 1
        let hot = LiveJSON.int(LiveJSON.object(room["room_biz_all"])?["hot"])
        return LiveRoomDetail(
            platform: .douyu,
            roomId: rid,
            title: LiveJSON.string(room["room_name"]),
            cover: LiveJSON.string(room["room_pic"]),
            userName: LiveJSON.string(room["owner_name"]),
            userAvatar: LiveJSON.string(room["owner_avatar"]),
            online: hot,
            isLive: isLive,
            webURL: "https://www.douyu.com/\(rid)",
            introduction: LiveJSON.string(room["show_details"]),
            playContextJSON: LiveJSON.encode(["sign": sign, "roomId": rid]),
            danmakuJSON: LiveJSON.encode(["roomId": rid])
        )
    }

    func getPlayQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        let ctx = LiveJSON.decodeObject(detail.playContextJSON)
        var body = LiveJSON.string(ctx["sign"])
        guard !body.isEmpty else { throw NetworkError.message("斗鱼签名为空") }
        body += "&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0"
        let json = try await postForm(
            "https://www.douyu.com/lapi/live/getH5Play/\(detail.roomId)",
            body: body,
            headers: [
                "Referer": "https://www.douyu.com/\(detail.roomId)",
                "User-Agent": ua
            ]
        )
        guard let data = LiveJSON.object(json["data"]) else {
            throw NetworkError.message(LiveJSON.string(json["msg"]).isEmpty ? "斗鱼清晰度获取失败" : LiveJSON.string(json["msg"]))
        }
        var cdns = (LiveJSON.array(data["cdnsWithName"]) ?? []).map { LiveJSON.string($0["cdn"]) }.filter { !$0.isEmpty }
        cdns.sort { a, b in
            if a.hasPrefix("scdn") && !b.hasPrefix("scdn") { return false }
            if !a.hasPrefix("scdn") && b.hasPrefix("scdn") { return true }
            return false
        }
        let rates = LiveJSON.array(data["multirates"]) ?? []
        return rates.enumerated().map { idx, item in
            LivePlayQuality(
                id: "douyu-\(LiveJSON.int(item["rate"]))-\(idx)",
                name: LiveJSON.string(item["name"]),
                qn: LiveJSON.int(item["rate"]),
                cdns: cdns,
                formBody: LiveJSON.string(ctx["sign"])
            )
        }
    }

    func getPlayURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        guard let formBody = quality.formBody, !formBody.isEmpty else {
            throw NetworkError.message("斗鱼播放参数缺失")
        }
        var urls: [String] = []
        for cdn in quality.cdns {
            let body = "\(formBody)&cdn=\(cdn)&rate=\(quality.qn)"
            do {
                let json = try await postForm(
                    "https://www.douyu.com/lapi/live/getH5Play/\(detail.roomId)",
                    body: body,
                    headers: [
                        "Referer": "https://www.douyu.com/\(detail.roomId)",
                        "User-Agent": ua
                    ]
                )
                if let data = LiveJSON.object(json["data"]) {
                    let base = LiveJSON.string(data["rtmp_url"])
                    let live = htmlUnescape(LiveJSON.string(data["rtmp_live"]))
                    if !base.isEmpty, !live.isEmpty {
                        let full = "\(base)/\(live)"
                        urls.append(full)
                        // Some lines expose flv; try sibling m3u8 for AVPlayer.
                        if full.contains(".flv") {
                            urls.append(full.replacingOccurrences(of: ".flv", with: ".m3u8"))
                        }
                    }
                    // Explicit HLS fields if present
                    for key in ["hls_url", "https_hls_url", "rtmp_hls"] {
                        let h = htmlUnescape(LiveJSON.string(data[key]))
                        if h.contains("m3u8") { urls.append(h) }
                    }
                }
            } catch {
                continue
            }
        }
        guard !urls.isEmpty else { throw NetworkError.message("斗鱼无可用播放地址") }
        return LivePlayResult(urls: urls, headers: [
            "User-Agent": ua,
            "Referer": "https://www.douyu.com/\(detail.roomId)"
        ])
    }

    // MARK: - Internals

    private func getRoomInfo(_ roomId: String) async throws -> [String: Any] {
        let json = try await getJSON(
            "https://www.douyu.com/betard/\(roomId)",
            headers: [
                "Referer": "https://www.douyu.com/\(roomId)",
                "User-Agent": ua
            ]
        )
        if let room = LiveJSON.object(json["room"]) { return room }
        throw NetworkError.message("斗鱼房间信息为空")
    }

    private func parseHot(_ hn: String) -> Int {
        let s = hn.replacingOccurrences(of: "万", with: "")
        guard var n = Double(s) else { return 0 }
        if hn.contains("万") { n *= 10_000 }
        return Int(n.rounded())
    }

    private func htmlUnescape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private func randomHex(_ length: Int) -> String {
        let chars = Array("0123456789abcdef")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private func getJSON(
        _ url: String,
        query: [String: String] = [:],
        headers: [String: String] = [:]
    ) async throws -> [String: Any] {
        let text = try await getText(url, query: query, headers: headers)
        guard let data = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("斗鱼 JSON 解析失败")
        }
        return obj
    }

    private func getText(
        _ url: String,
        query: [String: String] = [:],
        headers: [String: String] = [:]
    ) async throws -> String {
        var comps = URLComponents(string: url)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let final = comps.url else { throw NetworkError.invalidURL }
        var req = URLRequest(url: final)
        req.timeoutInterval = 25
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func postForm(
        _ url: String,
        body: String,
        headers: [String: String]
    ) async throws -> [String: Any] {
        guard let final = URL(string: url) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: final)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("斗鱼播放接口解析失败")
        }
        return obj
    }
}
