import Foundation
import CryptoKit

/// Pure helpers (no actor) so SwiftUI can call without hopping isolation.
enum LiveBilibiliIDs {
    /// Extract room id from `live.bilibili.com/123` / pure digits / query params.
    static func extractRoomId(from text: String) -> String? {
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
}

/// Bilibili live APIs ported from SimpleLive `bilibili_site.dart`
/// https://github.com/xiaoyaocz/dart_simple_live/blob/master/simple_live_core/lib/src/bilibili_site.dart
///
/// Playback notes (match SimpleLive media_kit path):
/// - Qualities: format=0,1,2 codec=0,1
/// - Play URLs: format=0,2 codec=**0 only** (AVC/H.264) — HEVC (codec=1) crashes many LibVLC builds
/// - Stream headers: Referer + User-Agent only (no Cookie on CDN)
actor BilibiliLiveService {
    static let shared = BilibiliLiveService()

    private let ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0"
    /// Play headers UA (SimpleLive getPlayUrls).
    private let playUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36 Edg/115.0.1901.188"
    private let referer = "https://live.bilibili.com/"

    private var buvid3 = ""
    private var buvid4 = ""
    private var imgKey = ""
    private var subKey = ""
    private var lastPlayInfoAt: Date = .distantPast

    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
        33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
        26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

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

    nonisolated static func extractRoomId(from text: String) -> String? {
        LiveBilibiliIDs.extractRoomId(from: text)
    }

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

    private func dictArray(_ any: Any?) -> [[String: Any]] {
        if let a = any as? [[String: Any]] { return a }
        if let a = any as? [Any] { return a.compactMap { dict($0) } }
        if let a = any as? NSArray { return a.compactMap { dict($0) } }
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

    private func stripTags(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inTag = false
        for ch in text {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
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

    // MARK: - Public API (SimpleLive LiveSite)

    func getCategories() async throws -> [LiveCategory] {
        let json = try await getJSON(
            "https://api.live.bilibili.com/room/v1/Area/getList",
            query: ["need_entrance": "1", "parent_id": "0"],
            signed: false
        )
        return dictArray(json["data"]).map { item in
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
        return dictArray(dict(json["data"])?["list"]).compactMap { mapRoom($0) }
    }

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Room id / link → stub (detail loads on enter), same as SimpleLive UX.
        if let rid = LiveBilibiliIDs.extractRoomId(from: trimmed),
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

        // SimpleLive: search_type=live → result.live_room
        if let rooms = try? await searchLiveRooms(keyword: trimmed, page: page, searchType: "live"),
           !rooms.isEmpty {
            return rooms
        }
        // Fallback flat list
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
            items = dictArray(resultDict["live_room"])
            if items.isEmpty {
                items = dictArray(resultDict["live_user"])
            }
        } else {
            items = dictArray(resultAny)
        }

        var out: [LiveRoomItem] = []
        var seen = Set<String>()
        for item in items {
            guard let room = mapRoom(item) else { continue }
            if seen.insert(room.roomId).inserted {
                out.append(room)
            }
        }
        return out
    }

    /// SimpleLive `getRoomDetail`: getInfoByRoom + soft danmu token.
    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { throw NetworkError.message("房间号为空") }

        // Primary: WBI getInfoByRoom (SimpleLive).
        if let d = try? await roomDetailFromInfoByRoom(roomId: rid) {
            return await withSoftDanmaku(d)
        }
        // Fallback: get_info (no WBI).
        if let d = try? await roomDetailFromGetInfo(roomId: rid) {
            return await withSoftDanmaku(d)
        }
        // Last resort: play-info live_status only.
        if let d = try? await roomDetailFromPlayInfo(roomId: rid) {
            return d
        }
        throw NetworkError.message("无法获取直播间信息")
    }

    private func withSoftDanmaku(_ detail: LiveRoomDetail) async -> LiveRoomDetail {
        var d = detail
        if let danmu = try? await getDanmuInfo(roomId: d.roomId) {
            d.danmakuJSON = LiveJSON.encodeJSONSafe(danmu)
        }
        return d
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

    private func roomDetailFromGetInfo(roomId: String) async throws -> LiveRoomDetail {
        let json = try await getJSON(
            "https://api.live.bilibili.com/room/v1/Room/get_info",
            query: ["room_id": roomId],
            signed: false
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

    private func roomDetailFromPlayInfo(roomId: String) async throws -> LiveRoomDetail {
        let data = try await roomPlayInfoData(
            roomId: roomId,
            qn: nil,
            format: "0,1,2",
            codec: "0,1"
        )
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

    /// Token + host for live chat WebSocket (SimpleLive `BiliBiliDanmakuArgs`). Soft-fail OK.
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
        return [
            "roomId": intVal(roomId),
            "token": str(data["token"]),
            "serverHost": hosts.first ?? "broadcastlv.chat.bilibili.com",
            "buvid": buvid3,
            "uid": userIdFromCookie,
            "cookie": cookie
        ]
    }

    // MARK: - Play (SimpleLive getPlayQualites / getPlayUrls)

    func getPlayQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        try await getPlayQualities(roomId: detail.roomId)
    }

    func getPlayQualities(roomId: String) async throws -> [LivePlayQuality] {
        // SimpleLive: protocol 0,1 / format 0,1,2 / codec 0,1
        let play = try await roomPlayInfo(
            roomId: roomId,
            qn: nil,
            format: "0,1,2",
            codec: "0,1"
        )
        var map: [Int: String] = [:]
        for item in dictArray(play["g_qn_desc"]) {
            let qn = intVal(item["qn"])
            if qn > 0 {
                map[qn] = str(item["desc"]).ifEmpty("\(qn)")
            }
        }
        // SimpleLive only reads first stream/format/codec accept_qn for quality list.
        var accepted = Set<Int>()
        let streams = dictArray(play["stream"])
        if let firstStream = streams.first {
            let formats = dictArray(firstStream["format"])
            if let firstFormat = formats.first {
                let codecs = dictArray(firstFormat["codec"])
                if let firstCodec = codecs.first {
                    if let arr = firstCodec["accept_qn"] as? [Any] {
                        for a in arr {
                            let q = intVal(a)
                            if q > 0 { accepted.insert(q) }
                        }
                    } else if let arr = firstCodec["accept_qn"] as? [Int] {
                        accepted.formUnion(arr.filter { $0 > 0 })
                    }
                }
            }
        }
        // Also union all codecs for richer list (defensive).
        if accepted.isEmpty {
            for stream in streams {
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
        }
        var qualities: [LivePlayQuality] = accepted.sorted(by: >).map { qn in
            LivePlayQuality(name: map[qn] ?? "\(qn)", qn: qn)
        }
        if qualities.isEmpty {
            // SimpleLive throws; we offer common qn so UI still works.
            qualities = [
                LivePlayQuality(name: "原画", qn: 10000),
                LivePlayQuality(name: "蓝光", qn: 400),
                LivePlayQuality(name: "超清", qn: 250),
                LivePlayQuality(name: "高清", qn: 150),
                LivePlayQuality(name: "流畅", qn: 80)
            ]
        }
        return qualities
    }

    func getPlayURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        try await getPlayURLs(roomId: detail.roomId, qn: quality.qn)
    }

    func getPlayURLs(roomId: String, qn: Int) async throws -> LivePlayResult {
        // SimpleLive getPlayUrls: format=0,2 codec=0 (AVC only) platform=web qn=…
        let play = try await roomPlayInfo(
            roomId: roomId,
            qn: qn,
            format: "0,2",
            codec: "0"
        )
        var urls: [String] = []
        for stream in dictArray(play["stream"]) {
            for format in dictArray(stream["format"]) {
                for codec in dictArray(format["codec"]) {
                    let codecName = str(codec["codec_name"]).lowercased()
                    // Extra guard: never return HEVC to LibVLC.
                    if codecName.contains("hevc") || codecName.contains("h265") || codecName == "hev1" {
                        continue
                    }
                    let baseURL = str(codec["base_url"])
                    for info in dictArray(codec["url_info"]) {
                        let host = str(info["host"])
                        let extra = str(info["extra"])
                        let full = host + baseURL + extra
                        guard full.hasPrefix("http"), URL(string: full) != nil else { continue }
                        urls.append(full)
                    }
                }
            }
        }
        // SimpleLive: mcdn last.
        urls.sort { a, b in
            let am = a.contains("mcdn")
            let bm = b.contains("mcdn")
            if am != bm { return !am && bm }
            return false
        }
        var seen = Set<String>()
        urls = urls.filter { seen.insert($0).inserted }
        guard !urls.isEmpty else {
            throw NetworkError.message("未获取到可播放地址（可配置设置中的 B站 Cookie 后重试）")
        }
        // SimpleLive play headers: referer + user-agent only (no Cookie on CDN).
        return LivePlayResult(urls: urls, headers: [
            "Referer": "https://live.bilibili.com",
            "User-Agent": playUA
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
        format: String,
        codec: String
    ) async throws -> [String: Any] {
        try await throttlePlayInfo()
        var params: [String: String] = [
            "room_id": roomId,
            "protocol": "0,1",
            "format": format,
            "codec": codec,
            "platform": "web"
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

    private func roomPlayInfo(
        roomId: String,
        qn: Int?,
        format: String,
        codec: String
    ) async throws -> [String: Any] {
        let data = try await roomPlayInfoData(
            roomId: roomId,
            qn: qn,
            format: format,
            codec: codec
        )
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
        // Prefer buvid from user cookie if present (SimpleLive getBuvid).
        let c = userCookie
        if c.contains("buvid3") {
            if let m = c.range(of: #"buvid3=([^;]+)"#, options: .regularExpression) {
                let cap = String(c[m]).replacingOccurrences(of: "buvid3=", with: "")
                buvid3 = cap
            }
            if let m = c.range(of: #"buvid4=([^;]+)"#, options: .regularExpression) {
                let cap = String(c[m]).replacingOccurrences(of: "buvid4=", with: "")
                buvid4 = cap
            }
            if !buvid3.isEmpty { return }
        }
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
            // Keep empty — play may still work.
        }
    }

    private func wbiSign(_ params: [String: String]) async throws -> [String: String] {
        let (img, sub) = try await wbiKeys()
        guard !img.isEmpty, !sub.isEmpty else { return params }
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
        guard var comps = URLComponents(string: url) else { throw NetworkError.invalidURL }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
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
        guard !data.isEmpty else { throw NetworkError.message("空响应") }
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
    var nonZero: Int? { self > 0 ? self : nil }
}

private extension String {
    func ifEmpty(_ alt: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? alt : self
    }
}
