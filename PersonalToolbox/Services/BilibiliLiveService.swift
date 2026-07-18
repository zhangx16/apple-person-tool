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
            webURL: "https://live.bilibili.com/\(roomId)",
            introduction: "\(room["description"] ?? "")"
        )
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
            qualities.append(LivePlayQuality(name: map[qn] ?? "\(qn)", qn: qn))
        }
        if qualities.isEmpty {
            // fallback common qn
            qualities = [
                LivePlayQuality(name: "原画", qn: 10000),
                LivePlayQuality(name: "蓝光", qn: 400),
                LivePlayQuality(name: "超清", qn: 250),
                LivePlayQuality(name: "高清", qn: 150)
            ]
        }
        return qualities
    }

    func getPlayURLs(roomId: String, qn: Int) async throws -> LivePlayResult {
        let play = try await roomPlayInfo(roomId: roomId, qn: qn)
        var urls: [String] = []
        for stream in (play["stream"] as? [[String: Any]]) ?? [] {
            for format in (stream["format"] as? [[String: Any]]) ?? [] {
                for codec in (format["codec"] as? [[String: Any]]) ?? [] {
                    let baseURL = "\(codec["base_url"] ?? "")"
                    for info in (codec["url_info"] as? [[String: Any]]) ?? [] {
                        let host = "\(info["host"] ?? "")"
                        let extra = "\(info["extra"] ?? "")"
                        let full = host + baseURL + extra
                        if full.hasPrefix("http") { urls.append(full) }
                    }
                }
            }
        }
        urls.sort { a, b in
            if a.contains("mcdn") { return false }
            if b.contains("mcdn") { return true }
            return false
        }
        guard !urls.isEmpty else { throw NetworkError.message("未获取到播放地址") }
        return LivePlayResult(urls: urls, headers: [
            "Referer": "https://live.bilibili.com",
            "User-Agent": ua
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

    private func roomPlayInfo(roomId: String, qn: Int?) async throws -> [String: Any] {
        var params: [String: String] = [
            "room_id": roomId,
            "protocol": "0,1",
            "format": "0,1,2",
            "codec": "0,1",
            "platform": "web"
        ]
        if let qn { params["qn"] = "\(qn)" }
        let json = try await getJSON(
            "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
            query: params
        )
        guard let data = json["data"] as? [String: Any],
              let playurlInfo = data["playurl_info"] as? [String: Any],
              let playurl = playurlInfo["playurl"] as? [String: Any] else {
            let msg = "\(json["message"] ?? "播放信息异常")"
            throw NetworkError.message(msg)
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
            let v = p[k]!.filter { !"!'()*".contains($0) }
            filtered[k] = v
        }
        let query = filtered.keys.sorted().map { key in
            let enc = filtered[key]!.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filtered[key]!
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

    private func getJSON(_ url: String, query: [String: String], signed: Bool = true) async throws -> [String: Any] {
        var q = query
        if signed, !query.isEmpty {
            // already signed by caller when needed
        }
        var comps = URLComponents(string: url)!
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
        if let code = obj["code"] as? Int, code != 0 {
            let msg = "\(obj["message"] ?? obj["msg"] ?? "错误 \(code)")"
            // some endpoints return code -352 without fully failing list - still throw
            if code != 0 { throw NetworkError.message(msg) }
        }
        return obj
    }
}
