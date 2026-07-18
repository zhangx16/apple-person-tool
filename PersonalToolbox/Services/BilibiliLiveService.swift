import Foundation
import CryptoKit

/// Bilibili live APIs ported from SimpleLive `bilibili_site.dart` (read-only).
actor BilibiliLiveService {
    static let shared = BilibiliLiveService()

    private let ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    private let referer = "https://live.bilibili.com/"

    private var buvid3 = ""
    private var buvid4 = ""
    private var imgKey = ""
    private var subKey = ""

    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
        33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
        26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

    // MARK: - Public

    func getCategories() async throws -> [LiveCategory] {
        let json = try await getJSON(
            "https://api.live.bilibili.com/room/v1/Area/getList",
            query: ["need_entrance": "1", "parent_id": "0"],
            signed: false
        )
        let data = json["data"] as? [[String: Any]] ?? []
        return data.map { item in
            let parentId = "\(item["id"] ?? "")"
            let subs = (item["list"] as? [[String: Any]] ?? []).map { sub in
                var pic = "\(sub["pic"] ?? "")"
                if !pic.isEmpty, !pic.contains("@") { pic += "@100w.png" }
                return LiveSubCategory(
                    id: "\(sub["id"] ?? "")",
                    name: "\(sub["name"] ?? "")",
                    parentId: "\(sub["parent_id"] ?? parentId)",
                    pic: pic
                )
            }
            return LiveCategory(id: parentId, name: "\(item["name"] ?? "")", children: subs)
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
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { mapRoom($0) }
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
        let list = (json["data"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
        return list.compactMap { mapRoom($0) }
    }

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        let base = "https://api.bilibili.com/x/web-interface/search/type"
        let params: [String: String] = [
            "search_type": "live",
            "cover_type": "user_cover",
            "keyword": keyword,
            "page": "\(page)",
            "highlight": "0",
            "single_column": "0"
        ]
        let json = try await getJSON(base, query: params)
        let liveRoom = ((json["data"] as? [String: Any])?["result"] as? [String: Any])?["live_room"] as? [[String: Any]] ?? []
        return liveRoom.compactMap { item in
            var title = "\(item["title"] ?? "")"
            title = title.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let roomId = "\(item["roomid"] ?? "")"
            guard !roomId.isEmpty else { return nil }
            var cover = "\(item["cover"] ?? "")"
            if cover.hasPrefix("//") { cover = "https:" + cover }
            if !cover.isEmpty, !cover.contains("@") { cover += "@400w.jpg" }
            return LiveRoomItem(
                platform: .bilibili,
                roomId: roomId,
                title: title,
                cover: cover,
                userName: "\(item["uname"] ?? "")",
                online: Int("\(item["online"] ?? 0)") ?? 0
            )
        }
    }

    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        // Prefer legacy get_info (stable). getInfoByRoom often returns -352 without full WBI risk pass.
        if let d = try? await roomDetailFromGetInfo(roomId: roomId) {
            return d
        }
        if let d = try? await roomDetailFromInfoByRoom(roomId: roomId) {
            return d
        }
        // Last resort: play-info only (has live_status).
        return try await roomDetailFromPlayInfo(roomId: roomId)
    }

    private func roomDetailFromGetInfo(roomId: String) async throws -> LiveRoomDetail {
        let json = try await getJSON(
            "https://api.live.bilibili.com/room/v1/Room/get_info",
            query: ["room_id": roomId],
            signed: false,
            allowBusinessError: false
        )
        guard let room = json["data"] as? [String: Any] else {
            throw NetworkError.message("无法获取直播间信息")
        }
        let realId = "\(room["room_id"] ?? roomId)"
        var cover = "\(room["user_cover"] ?? room["keyframe"] ?? room["cover"] ?? "")"
        if cover.hasPrefix("//") { cover = "https:" + cover }
        var uname = "\(room["uname"] ?? "")"
        if uname.isEmpty {
            // get_info sometimes omits uname; leave blank
            uname = ""
        }
        return LiveRoomDetail(
            platform: .bilibili,
            roomId: realId,
            title: "\(room["title"] ?? "")",
            cover: cover,
            userName: uname,
            userAvatar: "",
            online: Int("\(room["online"] ?? room["attention"] ?? 0)") ?? 0,
            isLive: (Int("\(room["live_status"] ?? 0)") ?? 0) == 1,
            webURL: "https://live.bilibili.com/\(realId)",
            introduction: "\(room["description"] ?? "")",
            danmakuJSON: "{}"
        )
    }

    private func roomDetailFromInfoByRoom(roomId: String) async throws -> LiveRoomDetail {
        let base = "https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom"
        var params = ["room_id": roomId]
        params = try await wbiSign(params)
        let json = try await getJSON(base, query: params)
        guard let data = json["data"] as? [String: Any],
              let room = data["room_info"] as? [String: Any] else {
            throw NetworkError.message("无法获取直播间信息")
        }
        let realId = "\(room["room_id"] ?? roomId)"
        let anchor = (data["anchor_info"] as? [String: Any])?["base_info"] as? [String: Any]
        var face = "\(anchor?["face"] ?? "")"
        if !face.isEmpty, !face.contains("@") { face += "@100w.jpg" }
        return LiveRoomDetail(
            platform: .bilibili,
            roomId: realId,
            title: "\(room["title"] ?? "")",
            cover: "\(room["cover"] ?? "")",
            userName: "\(anchor?["uname"] ?? "")",
            userAvatar: face,
            online: Int("\(room["online"] ?? 0)") ?? 0,
            isLive: (Int("\(room["live_status"] ?? 0)") ?? 0) == 1,
            webURL: "https://live.bilibili.com/\(realId)",
            introduction: "\(room["description"] ?? "")",
            danmakuJSON: "{}"
        )
    }

    private func roomDetailFromPlayInfo(roomId: String) async throws -> LiveRoomDetail {
        let data = try await roomPlayInfoData(roomId: roomId, qn: 250)
        let live = (Int("\(data["live_status"] ?? 0)") ?? 0) == 1
        let realId = "\(data["room_id"] ?? roomId)"
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

    /// Token + host for live chat WebSocket.
    func getDanmuInfo(roomId: String) async throws -> [String: Any] {
        var params = ["id": roomId]
        params = try await wbiSign(params)
        let json = try await getJSON(
            "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo",
            query: params
        )
        guard let data = json["data"] as? [String: Any] else {
            throw NetworkError.message("弹幕服务器信息不可用")
        }
        let hosts = (data["host_list"] as? [[String: Any]] ?? []).compactMap { $0["host"] as? String }
        if buvid3.isEmpty { await refreshBuvid() }
        return [
            "roomId": Int(roomId) ?? 0,
            "token": "\(data["token"] ?? "")",
            "serverHost": hosts.first ?? "broadcastlv.chat.bilibili.com",
            "buvid": buvid3,
            "uid": 0,
            "cookie": "buvid3=\(buvid3);buvid4=\(buvid4);"
        ]
    }

    func getPlayQualities(roomId: String) async throws -> [LivePlayQuality] {
        let play = try await roomPlayInfo(roomId: roomId, qn: nil)
        var map: [Int: String] = [:]
        for item in (play["g_qn_desc"] as? [[String: Any]]) ?? [] {
            let qn = Int("\(item["qn"] ?? 0)") ?? 0
            map[qn] = "\(item["desc"] ?? "清晰度")"
        }
        let streams = play["stream"] as? [[String: Any]] ?? []
        let formats = (streams.first?["format"] as? [[String: Any]]) ?? []
        let codecs = (formats.first?["codec"] as? [[String: Any]]) ?? []
        let accepted = (codecs.first?["accept_qn"] as? [Any]) ?? []
        var qualities: [LivePlayQuality] = []
        for a in accepted {
            let qn = Int("\(a)") ?? 0
            if qn > 0 {
                qualities.append(LivePlayQuality(name: map[qn] ?? "\(qn)", qn: qn))
            }
        }
        if qualities.isEmpty {
            // iOS-friendly ladder (prefer mid rates first in UI order)
            qualities = [
                LivePlayQuality(name: "高清", qn: 250),
                LivePlayQuality(name: "超清", qn: 400),
                LivePlayQuality(name: "流畅", qn: 150),
                LivePlayQuality(name: "原画", qn: 10000)
            ]
        }
        return qualities
    }

    func getPlayURLs(roomId: String, qn: Int) async throws -> LivePlayResult {
        // Request HLS-capable formats. AVPlayer cannot play FLV.
        let play = try await roomPlayInfo(roomId: roomId, qn: qn)
        struct Cand {
            var url: String
            var score: Int
        }
        var cands: [Cand] = []
        for stream in (play["stream"] as? [[String: Any]]) ?? [] {
            for format in (stream["format"] as? [[String: Any]]) ?? [] {
                let formatName = "\(format["format_name"] ?? "")".lowercased()
                for codec in (format["codec"] as? [[String: Any]]) ?? [] {
                    let codecName = "\(codec["codec_name"] ?? "")".lowercased()
                    let baseURL = "\(codec["base_url"] ?? "")"
                    for info in (codec["url_info"] as? [[String: Any]]) ?? [] {
                        let host = "\(info["host"] ?? "")"
                        let extra = "\(info["extra"] ?? "")"
                        let full = host + baseURL + extra
                        guard full.hasPrefix("http") else { continue }
                        // Score for AVPlayer: HLS first, AVC over HEVC, avoid mcdn.
                        var score = 0
                        if full.contains(".m3u8") || formatName == "ts" || formatName == "fmp4" {
                            score += 100
                        }
                        if formatName == "fmp4" { score += 20 }
                        if formatName == "ts" { score += 15 }
                        if formatName == "flv" || full.contains(".flv") { score -= 200 }
                        if codecName.contains("avc") || codecName.contains("h264") { score += 30 }
                        if codecName.contains("hevc") || codecName.contains("h265") { score -= 10 }
                        if full.contains("mcdn") { score -= 40 }
                        cands.append(Cand(url: full, score: score))
                    }
                }
            }
        }
        // Keep only positive scores (HLS-like); if empty, keep original non-flv.
        var picked = cands.filter { $0.score >= 100 }.sorted { $0.score > $1.score }.map(\.url)
        if picked.isEmpty {
            picked = cands.filter { !$0.url.contains(".flv") }.sorted { $0.score > $1.score }.map(\.url)
        }
        // Dedupe preserve order
        var seen = Set<String>()
        picked = picked.filter { seen.insert($0).inserted }
        guard !picked.isEmpty else { throw NetworkError.message("未获取到可播放地址（HLS）") }

        if buvid3.isEmpty { await refreshBuvid() }
        return LivePlayResult(urls: picked, headers: [
            "Referer": "https://live.bilibili.com",
            "Origin": "https://live.bilibili.com",
            "User-Agent": ua,
            "Cookie": "buvid3=\(buvid3);buvid4=\(buvid4);"
        ])
    }

    // MARK: - Internals

    private func mapRoom(_ item: [String: Any]) -> LiveRoomItem? {
        let roomId = "\(item["roomid"] ?? item["room_id"] ?? "")"
        guard !roomId.isEmpty else { return nil }
        var cover = "\(item["cover"] ?? item["user_cover"] ?? "")"
        if !cover.isEmpty, !cover.contains("@") { cover += "@400w.jpg" }
        return LiveRoomItem(
            platform: .bilibili,
            roomId: roomId,
            title: "\(item["title"] ?? "")",
            cover: cover,
            userName: "\(item["uname"] ?? "")",
            online: Int("\(item["online"] ?? 0)") ?? 0
        )
    }

    private func roomPlayInfoData(roomId: String, qn: Int?) async throws -> [String: Any] {
        var params: [String: String] = [
            "room_id": roomId,
            "protocol": "0,1",
            // 0=flv 1=ts 2=fmp4 — still request all; client filters for AVPlayer
            "format": "0,1,2",
            "codec": "0,1",
            "platform": "web",
            "dolby": "5",
            "panorama": "1"
        ]
        if let qn { params["qn"] = "\(qn)" }
        let json = try await getJSON(
            "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
            query: params,
            signed: false
        )
        guard let data = json["data"] as? [String: Any] else {
            let msg = "\(json["message"] ?? "播放信息异常")"
            throw NetworkError.message(msg)
        }
        return data
    }

    private func roomPlayInfo(roomId: String, qn: Int?) async throws -> [String: Any] {
        let data = try await roomPlayInfoData(roomId: roomId, qn: qn)
        guard let playurlInfo = data["playurl_info"] as? [String: Any],
              let playurl = playurlInfo["playurl"] as? [String: Any] else {
            // Offline rooms have empty playurl_info
            if (Int("\(data["live_status"] ?? 0)") ?? 0) != 1 {
                throw NetworkError.message("当前未开播")
            }
            throw NetworkError.message("播放信息异常")
        }
        return playurl
    }

    private func headers() async -> [String: String] {
        if buvid3.isEmpty {
            await refreshBuvid()
        }
        return [
            "User-Agent": ua,
            "Referer": referer,
            "Cookie": "buvid3=\(buvid3);buvid4=\(buvid4);"
        ]
    }

    private func refreshBuvid() async {
        do {
            let json = try await getJSON(
                "https://api.bilibili.com/x/frontend/finger/spi",
                query: [:],
                signed: false
            )
            if let data = json["data"] as? [String: Any] {
                buvid3 = "\(data["b_3"] ?? "")"
                buvid4 = "\(data["b_4"] ?? "")"
            }
        } catch {
            buvid3 = ""
            buvid4 = ""
        }
    }

    private func wbiSign(_ params: [String: String]) async throws -> [String: String] {
        let (img, sub) = try await wbiKeys()
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
        let json = try await getJSON("https://api.bilibili.com/x/web-interface/nav", query: [:], signed: false)
        guard let data = json["data"] as? [String: Any],
              let wbi = data["wbi_img"] as? [String: Any] else {
            return ("", "")
        }
        let imgURL = "\(wbi["img_url"] ?? "")"
        let subURL = "\(wbi["sub_url"] ?? "")"
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
        var q = query
        guard var comps = URLComponents(string: url) else { throw NetworkError.invalidURL }
        if !q.isEmpty {
            comps.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let final = comps.url else { throw NetworkError.invalidURL }
        var req = URLRequest(url: final)
        req.timeoutInterval = 25
        let h = await headers()
        for (k, v) in h { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("JSON 解析失败")
        }
        if let code = obj["code"] as? Int, code != 0, !allowBusinessError {
            let msg = "\(obj["message"] ?? obj["msg"] ?? "错误 \(code)")"
            throw NetworkError.message(msg)
        }
        return obj
    }
}
