import Foundation
import CryptoKit

/// Bilibili live APIs ported from SimpleLive `bilibili_site.dart`
/// (https://github.com/xiaoyaocz/dart_simple_live).
///
/// Defensive parsing throughout: NSDictionary/NSArray bridging from
/// `JSONSerialization` must not use brittle `as? [[String: Any]]` alone
/// (nil cast → empty results or unexpected control flow on device).
actor BilibiliLiveService {
    static let shared = BilibiliLiveService()

    private let ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0"
    private let referer = "https://live.bilibili.com/"

    private var buvid3 = ""
    private var buvid4 = ""
    private var imgKey = ""
    private var subKey = ""

    /// Serialize play-info requests (SimpleLive throttles ~450ms to avoid 429).
    private var lastPlayInfoAt: Date = .distantPast

    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
        33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
        26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

    /// Optional SESSDATA cookie from 设置 → B站 Cookie (shared with download).
    private var userCookie: String {
        (UserDefaults.standard.string(forKey: "bilibiliCookie") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var userIdFromCookie: Int {
        let c = userCookie
        guard !c.isEmpty else { return 0 }
        for part in c.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if kv.count == 2, kv[0] == "DedeUserID", let n = Int(kv[1]) {
                return n
            }
        }
        return 0
    }

    // MARK: - Helpers

    /// Extract room id from `live.bilibili.com/123` / pure digits.
    nonisolated static func extractRoomId(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return trimmed
        }
        let patterns = [
            #"live\.bilibili\.com/(?:h5/)?(\d+)"#,
            #"bilibili\.com/live/(\d+)"#,
            #"[?&]roomid=(\d+)"#,
            #"[?&]room_id=(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let m = regex.firstMatch(in: trimmed, range: range), m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: trimmed) {
                return String(trimmed[r])
            }
        }
        return nil
    }

    /// Safe string from heterogeneous JSON values (NSNumber / NSNull / nested).
    private func str(_ any: Any?) -> String {
        guard let any, !(any is NSNull) else { return "" }
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        if let i = any as? Int { return "\(i)" }
        if let i = any as? Int64 { return "\(i)" }
        if let d = any as? Double { return String(Int(d)) }
        return "\(any)"
    }

    private func intVal(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let i = any as? Int64 { return Int(i) }
        if let n = any as? NSNumber { return n.intValue }
        return Int(str(any)) ?? 0
    }

    private func dict(_ any: Any?) -> [String: Any]? {
        if let d = any as? [String: Any] { return d }
        if let d = any as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in d {
                if let ks = k as? String { out[ks] = v }
            }
            return out
        }
        return nil
    }

    /// NSArray / [[String: Any]] bridge-safe.
    private func dictArray(_ any: Any?) -> [[String: Any]] {
        if let a = any as? [[String: Any]] { return a }
        if let a = any as? [Any] {
            return a.compactMap { dict($0) }
        }
        if let a = any as? NSArray {
            return a.compactMap { dict($0) }
        }
        return []
    }

    private func absURL(_ raw: String, sizeSuffix: String = "") -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if s.hasPrefix("//") { s = "https:" + s }
        if s.hasPrefix("http://") || s.hasPrefix("https://") {
            // ok
        } else if s.hasPrefix("/") {
            s = "https://i0.hdslb.com" + s
        } else {
            s = "https://" + s
        }
        if !sizeSuffix.isEmpty, !s.contains("@") {
            s += sizeSuffix
        }
        return s
    }

    /// Strip HTML tags without NSRegularExpression (avoids rare ICU edge crashes).
    private func stripTags(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inTag = false
        for ch in text {
            if ch == "<" {
                inTag = true
                continue
            }
            if ch == ">" {
                inTag = false
                continue
            }
            if !inTag { out.append(ch) }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Public

    func getCategories() async throws -> [LiveCategory] {
        let json = try await getJSON(
            "https://api.live.bilibili.com/room/v1/Area/getList",
            query: ["need_entrance": "1", "parent_id": "0"],
            signed: false
        )
        let data = dictArray(json["data"])
        return data.map { item in
            let parentId = str(item["id"])
            let subs = dictArray(item["list"]).map { sub in
                LiveSubCategory(
                    id: str(sub["id"]),
                    name: str(sub["name"]),
                    parentId: str(sub["parent_id"]).ifEmpty(parentId),
                    pic: absURL(str(sub["pic"]), sizeSuffix: "@100w.png")
                )
            }
            return LiveCategory(id: parentId, name: str(item["name"]), children: subs)
        }
    }

    func getCategoryRooms(category: LiveSubCategory, page: Int = 1) async throws -> [LiveRoomItem] {
        let json = try await getJSON(
            "https://api.live.bilibili.com/room/v1/Area/getRoomList",
            query: [
                "platform": "web",
                "parent_area_id": category.parentId,
                "area_id": category.id,
                "page": "\(page)",
                "page_size": "30"
            ],
            signed: false
        )
        return dictArray(json["data"]).compactMap { mapRoom($0) }
    }

    func getRecommendRooms(page: Int = 1) async throws -> [LiveRoomItem] {
        let base = "https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea"
        var params = [
            "platform": "web",
            "sort": "online",
            "page_size": "30",
            "page": "\(page)"
        ]
        params = try await wbiSign(params)
        let json = try await getJSON(base, query: params)
        let list = dictArray(dict(json["data"])?["list"])
        return list.compactMap { mapRoom($0) }
    }

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Pure room id / short id: return a lightweight stub (detail loads on enter).
        // Avoid getRoomDetail here — it does WBI + danmu and used to make search feel like a crash when it failed hard.
        if let rid = Self.extractRoomId(from: trimmed),
           rid.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return [
                LiveRoomItem(
                    platform: .bilibili,
                    roomId: rid,
                    title: "房间 \(rid)",
                    cover: "",
                    userName: "",
                    online: 0
                )
            ]
        }

        // Primary: search_type=live → result.live_room
        if let rooms = try? await searchLiveRooms(keyword: trimmed, page: page, searchType: "live"),
           !rooms.isEmpty {
            return rooms
        }
        // Fallback: search_type=live_room → result is a flat list
        if let rooms = try? await searchLiveRooms(keyword: trimmed, page: page, searchType: "live_room"),
           !rooms.isEmpty {
            return rooms
        }
        return []
    }

    private func searchLiveRooms(keyword: String, page: Int, searchType: String) async throws -> [LiveRoomItem] {
        let base = "https://api.bilibili.com/x/web-interface/search/type"
        let params: [String: String] = [
            "search_type": searchType,
            "cover_type": "user_cover",
            "keyword": keyword,
            "page": "\(page)",
            "highlight": "0",
            "single_column": "0"
        ]
        let json = try await getJSON(base, query: params, signed: false)
        let data = dict(json["data"]) ?? [:]
        let resultAny = data["result"]

        var items: [[String: Any]] = []
        if let resultDict = dict(resultAny) {
            // { live_room: [...], live_user: [...] }
            items = dictArray(resultDict["live_room"])
            if items.isEmpty {
                items = dictArray(resultDict["live_user"])
            }
        } else {
            // Flat list (live_room search type)
            items = dictArray(resultAny)
        }

        var out: [LiveRoomItem] = []
        var seen = Set<String>()
        for item in items {
            guard let room = mapRoom(item) else { continue }
            // Dedupe — ForEach crash if duplicate Identifiable ids.
            if seen.insert(room.roomId).inserted {
                out.append(room)
            }
        }
        return out
    }

    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else {
            throw NetworkError.message("房间号为空")
        }

        var detail: LiveRoomDetail?
        // Prefer get_info first (no WBI, stable); then getInfoByRoom; then play stub.
        if let d = try? await roomDetailFromGetInfo(roomId: rid) {
            detail = d
        }
        if detail == nil, let d = try? await roomDetailFromInfoByRoom(roomId: rid) {
            detail = d
        }
        if detail == nil {
            detail = try await roomDetailFromPlayInfo(roomId: rid)
        }
        guard var resolved = detail else {
            throw NetworkError.message("无法获取直播间信息")
        }

        // Enrich empty fields from secondary source.
        if resolved.userName.isEmpty || resolved.userAvatar.isEmpty || resolved.cover.isEmpty {
            if let extra = try? await roomDetailFromInfoByRoom(roomId: resolved.roomId) {
                if resolved.userName.isEmpty { resolved.userName = extra.userName }
                if resolved.userAvatar.isEmpty { resolved.userAvatar = extra.userAvatar }
                if resolved.cover.isEmpty { resolved.cover = extra.cover }
                if resolved.title.isEmpty { resolved.title = extra.title }
                if resolved.categoryName.isEmpty { resolved.categoryName = extra.categoryName }
            }
        }

        // Danmaku token is best-effort (SimpleLive: must not block room open).
        if let danmu = try? await getDanmuInfo(roomId: resolved.roomId) {
            resolved.danmakuJSON = LiveJSON.encodeJSONSafe(danmu)
        }
        return resolved
    }

    private func roomDetailFromGetInfo(roomId: String) async throws -> LiveRoomDetail {
        let json = try await getJSON(
            "https://api.live.bilibili.com/room/v1/Room/get_info",
            query: ["room_id": roomId],
            signed: false,
            allowBusinessError: false
        )
        guard let room = dict(json["data"]) else {
            throw NetworkError.message("无法获取直播间信息")
        }
        let realId = str(room["room_id"]).ifEmpty(roomId)
        let intro = stripTags(str(room["description"]))
        return LiveRoomDetail(
            platform: .bilibili,
            roomId: realId,
            title: stripTags(str(room["title"])),
            cover: absURL(str(room["user_cover"]).ifEmpty(str(room["keyframe"])).ifEmpty(str(room["cover"]))),
            userName: str(room["uname"]),
            userAvatar: "",
            online: intVal(room["online"]).nonZero ?? intVal(room["attention"]),
            isLive: intVal(room["live_status"]) == 1,
            webURL: "https://live.bilibili.com/\(realId)",
            introduction: String(intro.prefix(500)),
            danmakuJSON: "{}",
            categoryName: str(room["area_name"])
        )
    }

    private func roomDetailFromInfoByRoom(roomId: String) async throws -> LiveRoomDetail {
        let base = "https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom"
        var params = ["room_id": roomId]
        params = try await wbiSign(params)
        let json = try await getJSON(base, query: params)
        guard let data = dict(json["data"]),
              let room = dict(data["room_info"]) else {
            throw NetworkError.message("无法获取直播间信息")
        }
        let realId = str(room["room_id"]).ifEmpty(roomId)
        let anchor = dict(dict(data["anchor_info"])?["base_info"])
        let intro = stripTags(str(room["description"]))
        return LiveRoomDetail(
            platform: .bilibili,
            roomId: realId,
            title: stripTags(str(room["title"])),
            cover: absURL(str(room["cover"])),
            userName: str(anchor?["uname"]),
            userAvatar: absURL(str(anchor?["face"]), sizeSuffix: "@100w.jpg"),
            online: intVal(room["online"]),
            isLive: intVal(room["live_status"]) == 1,
            webURL: "https://live.bilibili.com/\(realId)",
            introduction: String(intro.prefix(500)),
            danmakuJSON: "{}",
            categoryName: str(room["area_name"])
        )
    }

    private func roomDetailFromPlayInfo(roomId: String) async throws -> LiveRoomDetail {
        let data = try await roomPlayInfoData(roomId: roomId, qn: 250)
        let live = intVal(data["live_status"]) == 1
        let realId = str(data["room_id"]).ifEmpty(roomId)
        return LiveRoomDetail(
            platform: .bilibili,
            roomId: realId,
            title: "直播间 \(realId)",
            cover: "",
            userName: "",
            userAvatar: "",
            online: 0,
            isLive: live,
            webURL: "https://live.bilibili.com/\(realId)",
            introduction: "",
            danmakuJSON: "{}"
        )
    }

    /// Token + host for live chat WebSocket (SimpleLive `BiliBiliDanmakuArgs`).
    func getDanmuInfo(roomId: String) async throws -> [String: Any] {
        var params = ["id": roomId]
        params = try await wbiSign(params)
        let json = try await getJSON(
            "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo",
            query: params
        )
        guard let data = dict(json["data"]) else {
            throw NetworkError.message("弹幕服务器信息不可用")
        }
        let hosts = dictArray(data["host_list"]).compactMap { h -> String? in
            let host = str(h["host"])
            return host.isEmpty ? nil : host
        }
        if buvid3.isEmpty { await refreshBuvid() }
        let cookie = await cookieHeaderValue()
        // Only JSON-safe primitives (String / Int / Bool).
        return [
            "roomId": intVal(roomId),
            "token": str(data["token"]),
            "serverHost": hosts.first ?? "broadcastlv.chat.bilibili.com",
            "buvid": buvid3,
            "uid": userIdFromCookie,
            "cookie": cookie
        ]
    }

    // MARK: - Play (router API)

    func getPlayQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        try await getPlayQualities(roomId: detail.roomId)
    }

    func getPlayQualities(roomId: String) async throws -> [LivePlayQuality] {
        let play = try await roomPlayInfo(roomId: roomId, qn: nil)
        var map: [Int: String] = [:]
        for item in dictArray(play["g_qn_desc"]) {
            let qn = intVal(item["qn"])
            if qn > 0 {
                map[qn] = str(item["desc"]).ifEmpty("\(qn)")
            }
        }
        // Collect accept_qn across all streams/formats/codecs (not only first).
        var accepted = Set<Int>()
        for stream in dictArray(play["stream"]) {
            for format in dictArray(stream["format"]) {
                for codec in dictArray(format["codec"]) {
                    if let arr = codec["accept_qn"] as? [Any] {
                        for a in arr {
                            let q = intVal(a)
                            if q > 0 { accepted.insert(q) }
                        }
                    } else if let arr = codec["accept_qn"] as? [Int] {
                        accepted.formUnion(arr.filter { $0 > 0 })
                    }
                }
            }
        }
        var qualities: [LivePlayQuality] = accepted.sorted(by: >).map { qn in
            LivePlayQuality(name: map[qn] ?? "\(qn)", qn: qn)
        }
        if qualities.isEmpty {
            qualities = [
                LivePlayQuality(name: "高清", qn: 250),
                LivePlayQuality(name: "超清", qn: 400),
                LivePlayQuality(name: "流畅", qn: 150),
                LivePlayQuality(name: "原画", qn: 10000)
            ]
        }
        return qualities
    }

    func getPlayURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        try await getPlayURLs(roomId: detail.roomId, qn: quality.qn)
    }

    func getPlayURLs(roomId: String, qn: Int) async throws -> LivePlayResult {
        let play = try await roomPlayInfo(roomId: roomId, qn: qn, forPlayback: true)
        struct Cand {
            var url: String
            var score: Int
        }
        var cands: [Cand] = []
        for stream in dictArray(play["stream"]) {
            for format in dictArray(stream["format"]) {
                let formatName = str(format["format_name"]).lowercased()
                for codec in dictArray(format["codec"]) {
                    let codecName = str(codec["codec_name"]).lowercased()
                    // Skip HEVC on iOS — MobileVLCKit / some devices hard-crash on hevc live.
                    if codecName.contains("hevc") || codecName.contains("h265") || codecName == "hev1" {
                        continue
                    }
                    let baseURL = str(codec["base_url"])
                    for info in dictArray(codec["url_info"]) {
                        let host = str(info["host"])
                        let extra = str(info["extra"])
                        let full = host + baseURL + extra
                        guard full.hasPrefix("http"), URL(string: full) != nil else { continue }
                        var score = 50
                        if full.contains(".m3u8") || formatName == "ts" || formatName == "fmp4" {
                            score += 100
                        }
                        if formatName == "fmp4" { score += 25 }
                        if formatName == "ts" { score += 20 }
                        if formatName == "flv" || full.contains(".flv") { score += 10 }
                        if codecName.contains("avc") || codecName.contains("h264") { score += 40 }
                        if full.contains("mcdn") { score -= 50 }
                        cands.append(Cand(url: full, score: score))
                    }
                }
            }
        }
        var picked = cands.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let am = a.url.contains("mcdn")
            let bm = b.url.contains("mcdn")
            if am != bm { return !am && bm }
            return false
        }.map(\.url)
        var seen = Set<String>()
        picked = picked.filter { seen.insert($0).inserted }
        guard !picked.isEmpty else {
            throw NetworkError.message("未获取到可播放地址（可配置设置中的 B站 Cookie 后重试）")
        }

        if buvid3.isEmpty { await refreshBuvid() }
        let cookie = sanitizeHeader(await cookieHeaderValue())
        return LivePlayResult(urls: picked, headers: [
            "Referer": "https://live.bilibili.com",
            "Origin": "https://live.bilibili.com",
            "User-Agent": ua,
            "Cookie": cookie
        ])
    }

    // MARK: - Internals

    private func mapRoom(_ item: [String: Any]) -> LiveRoomItem? {
        let roomId = str(item["roomid"]).ifEmpty(str(item["room_id"]))
        guard !roomId.isEmpty, roomId != "0" else { return nil }
        let title = stripTags(str(item["title"]))
        let userName = stripTags(str(item["uname"]))
        let cover = absURL(
            str(item["cover"]).ifEmpty(str(item["user_cover"])).ifEmpty(str(item["system_cover"])),
            sizeSuffix: "@400w.jpg"
        )
        let face = absURL(
            str(item["uface"]).ifEmpty(str(item["face"])),
            sizeSuffix: "@100w.jpg"
        )
        let online = intVal(item["online"]).nonZero ?? intVal(item["attentions"])
        return LiveRoomItem(
            platform: .bilibili,
            roomId: roomId,
            title: title,
            cover: cover,
            userName: userName,
            online: online,
            userAvatar: face,
            categoryName: str(item["cate_name"]).ifEmpty(str(item["area_name"]))
        )
    }

    private func roomPlayInfoData(
        roomId: String,
        qn: Int?,
        forPlayback: Bool = false
    ) async throws -> [String: Any] {
        _ = forPlayback
        try await throttlePlayInfo()
        var params: [String: String] = [
            "room_id": roomId,
            "protocol": "0,1",
            "format": "0,1,2",
            "codec": "0,1",
            "platform": "web",
            "dolby": "5",
            "panorama": "1"
        ]
        if let qn { params["qn"] = "\(qn)" }

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let json = try await getJSON(
                    "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
                    query: params,
                    signed: false
                )
                guard let data = dict(json["data"]) else {
                    let msg = str(json["message"]).ifEmpty("播放信息异常")
                    throw NetworkError.message(msg)
                }
                return data
            } catch {
                lastError = error
                let msg = error.localizedDescription
                if msg.contains("429") || msg.contains("频繁"), attempt < 2 {
                    let ns: UInt64 = attempt == 0 ? 800_000_000 : 1_600_000_000
                    try? await Task.sleep(nanoseconds: ns)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? NetworkError.message("B站播放信息接口重试失败")
    }

    private func throttlePlayInfo() async {
        let minInterval: TimeInterval = 0.45
        let elapsed = Date().timeIntervalSince(lastPlayInfoAt)
        if elapsed < minInterval {
            let wait = UInt64((minInterval - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: wait)
        }
        lastPlayInfoAt = Date()
    }

    private func roomPlayInfo(roomId: String, qn: Int?, forPlayback: Bool = false) async throws -> [String: Any] {
        let data = try await roomPlayInfoData(roomId: roomId, qn: qn, forPlayback: forPlayback)
        guard let playurlInfo = dict(data["playurl_info"]),
              let playurl = dict(playurlInfo["playurl"]) else {
            if intVal(data["live_status"]) != 1 {
                throw NetworkError.message("当前未开播")
            }
            throw NetworkError.message("播放信息异常")
        }
        return playurl
    }

    private func cookieHeaderValue() async -> String {
        if buvid3.isEmpty {
            await refreshBuvid()
        }
        let custom = sanitizeHeader(userCookie)
        if custom.isEmpty {
            return "buvid3=\(buvid3);buvid4=\(buvid4);"
        }
        if custom.lowercased().contains("buvid3") {
            return custom
        }
        return "\(custom);buvid3=\(buvid3);buvid4=\(buvid4);"
    }

    private func headers() async -> [String: String] {
        [
            "User-Agent": ua,
            "Referer": referer,
            "Cookie": await cookieHeaderValue()
        ]
    }

    private func refreshBuvid() async {
        do {
            let json = try await getJSON(
                "https://api.bilibili.com/x/frontend/finger/spi",
                query: [:],
                signed: false
            )
            if let data = dict(json["data"]) {
                buvid3 = str(data["b_3"])
                buvid4 = str(data["b_4"])
            }
        } catch {
            // Keep previous or empty — play may still work without buvid.
        }
    }

    private func wbiSign(_ params: [String: String]) async throws -> [String: String] {
        let (img, sub) = try await wbiKeys()
        guard !img.isEmpty, !sub.isEmpty else {
            // Without keys, return params unsigned (get_info path doesn't need them).
            return params
        }
        let mixin = mixinKey(img + sub)
        var p = params
        p["wts"] = "\(Int(Date().timeIntervalSince1970))"
        let sortedKeys = p.keys.sorted()
        var filtered: [String: String] = [:]
        for k in sortedKeys {
            guard let raw = p[k] else { continue }
            let v = raw.filter { !"!'()*".contains($0) }
            filtered[k] = v
        }
        let query = filtered.keys.sorted().map { key in
            let val = filtered[key] ?? ""
            let enc = val.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? val
            return "\(key)=\(enc)"
        }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: Data((query + mixin).utf8))
        let rid = digest.map { String(format: "%02x", $0) }.joined()
        var out = p
        out["w_rid"] = rid
        return out
    }

    private func wbiKeys() async throws -> (String, String) {
        if !imgKey.isEmpty, !subKey.isEmpty { return (imgKey, subKey) }
        let json = try await getJSON(
            "https://api.bilibili.com/x/web-interface/nav",
            query: [:],
            signed: false,
            allowBusinessError: true
        )
        guard let data = dict(json["data"]),
              let wbi = dict(data["wbi_img"]) else {
            return ("", "")
        }
        let imgURL = str(wbi["img_url"])
        let subURL = str(wbi["sub_url"])
        imgKey = ((imgURL as NSString).lastPathComponent as NSString).deletingPathExtension
        subKey = ((subURL as NSString).lastPathComponent as NSString).deletingPathExtension
        return (imgKey, subKey)
    }

    private func mixinKey(_ origin: String) -> String {
        let chars = Array(origin)
        var s = ""
        for i in Self.mixinKeyEncTab {
            if i < chars.count { s.append(chars[i]) }
        }
        return String(s.prefix(32))
    }

    private func getJSON(
        _ url: String,
        query: [String: String],
        signed: Bool = true,
        allowBusinessError: Bool = false
    ) async throws -> [String: Any] {
        _ = signed
        let q = query
        guard var comps = URLComponents(string: url) else { throw NetworkError.invalidURL }
        if !q.isEmpty {
            comps.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let final = comps.url else { throw NetworkError.invalidURL }
        var req = URLRequest(url: final)
        req.timeoutInterval = 25
        let h = await headers()
        for (k, v) in h {
            req.setValue(sanitizeHeader(v), forHTTPHeaderField: k)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        if http.statusCode == 429 {
            throw NetworkError.message("请求过于频繁 (429)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else {
            throw NetworkError.message("空响应")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw NetworkError.message("JSON 解析失败")
        }
        guard let dictObj = dict(obj) else {
            throw NetworkError.message("JSON 格式异常")
        }
        if let code = dictObj["code"] as? Int, code != 0, !allowBusinessError {
            // Also handle NSNumber code
            let msg = str(dictObj["message"]).ifEmpty(str(dictObj["msg"])).ifEmpty("错误 \(code)")
            throw NetworkError.message(msg)
        }
        if let codeNum = dictObj["code"] as? NSNumber, codeNum.intValue != 0, !allowBusinessError {
            let code = codeNum.intValue
            let msg = str(dictObj["message"]).ifEmpty(str(dictObj["msg"])).ifEmpty("错误 \(code)")
            throw NetworkError.message(msg)
        }
        return dictObj
    }
}

// MARK: - Small helpers

private extension Int {
    /// `self` if > 0, else nil (for online fallback chain).
    var nonZero: Int? { self > 0 ? self : nil }
}

private extension String {
    func ifEmpty(_ alt: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? alt : self
    }
}
