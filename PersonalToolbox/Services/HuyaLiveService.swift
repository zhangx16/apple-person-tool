import Foundation

/// Huya live APIs ported from SimpleLive `huya_site.dart` v1.12.6.
/// Play URLs use page anticode + `processAnticode` (no Tars WUP client).
actor HuyaLiveService {
    static let shared = HuyaLiveService()

    private let mobileUA =
        "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0"
    private let playUA =
        "HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)"

    // MARK: - Public

    func getRecommendRooms(page: Int = 1) async throws -> [LiveRoomItem] {
        let json = try await getJSON(
            "https://www.huya.com/cache.php",
            query: [
                "m": "LiveList",
                "do": "getLiveListByPage",
                "tagAll": "0",
                "page": "\(page)"
            ]
        )
        let datas = LiveJSON.array(LiveJSON.object(json["data"])?["datas"]) ?? []
        return datas.compactMap { mapListItem($0) }
    }

    func searchRooms(keyword: String, page: Int = 1) async throws -> [LiveRoomItem] {
        let text = try await getText(
            "https://search.cdn.huya.com/",
            query: [
                "m": "Search",
                "do": "getSearchContent",
                "q": keyword,
                "uid": "0",
                "v": "4",
                "typ": "-5",
                "livestate": "0",
                "rows": "20",
                "start": "\((page - 1) * 20)"
            ]
        )
        guard let data = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("虎牙搜索解析失败")
        }
        let docs = LiveJSON.array(
            LiveJSON.object(LiveJSON.object(json["response"])?["3"])?["docs"]
        ) ?? []
        return docs.compactMap { item in
            var cover = LiveJSON.string(item["game_screenshot"])
            if !cover.isEmpty, !cover.contains("?") {
                cover += "?x-oss-process=style/w338_h190&"
            }
            var title = LiveJSON.string(item["game_introduction"])
            if title.isEmpty { title = LiveJSON.string(item["game_roomName"]) }
            let roomId = LiveJSON.string(item["room_id"])
            guard !roomId.isEmpty else { return nil }
            return LiveRoomItem(
                platform: .huya,
                roomId: roomId,
                title: title,
                cover: cover,
                userName: LiveJSON.string(item["game_nick"]),
                online: LiveJSON.int(item["game_total_count"])
            )
        }
    }

    func getRoomDetail(roomId: String) async throws -> LiveRoomDetail {
        let roomInfo = try await getRoomInfo(roomId)
        guard let roomInfoMap = LiveJSON.object(roomInfo["roomInfo"]),
              let tLiveInfo = LiveJSON.object(roomInfoMap["tLiveInfo"]),
              let tProfileInfo = LiveJSON.object(roomInfoMap["tProfileInfo"]) else {
            throw NetworkError.message("无法解析虎牙直播间")
        }
        let topSid = LiveJSON.int(roomInfo["topSid"])
        let subSid = LiveJSON.int(roomInfo["subSid"])
        var title = LiveJSON.string(tLiveInfo["sIntroduction"])
        if title.isEmpty { title = LiveJSON.string(tLiveInfo["sRoomName"]) }

        var lines: [[String: Any]] = []
        if let streamInfo = LiveJSON.object(tLiveInfo["tLiveStreamInfo"]),
           let vStream = LiveJSON.object(streamInfo["vStreamInfo"]),
           let values = LiveJSON.array(vStream["value"]) {
            for item in values {
                let flv = LiveJSON.string(item["sFlvUrl"])
                guard !flv.isEmpty else { continue }
                lines.append([
                    "line": flv,
                    "streamName": LiveJSON.string(item["sStreamName"]),
                    "flvAntiCode": LiveJSON.string(item["sFlvAntiCode"]),
                    "presenterUid": topSid > 0 ? topSid : subSid
                ])
            }
        }

        var bitRates: [[String: Any]] = []
        if let streamInfo = LiveJSON.object(tLiveInfo["tLiveStreamInfo"]),
           let vBit = LiveJSON.object(streamInfo["vBitRateInfo"]),
           let values = LiveJSON.array(vBit["value"]) {
            for item in values {
                let name = LiveJSON.string(item["sDisplayName"])
                if name.uppercased().contains("HDR") { continue }
                bitRates.append([
                    "name": name,
                    "bitRate": LiveJSON.int(item["iBitRate"])
                ])
            }
        }
        if bitRates.isEmpty {
            bitRates = [["name": "原画", "bitRate": 0], ["name": "高清", "bitRate": 2000]]
        }

        let uid = randomUid(length: 13)
        let ctx = LiveJSON.encode([
            "uid": uid,
            "lines": lines,
            "bitRates": bitRates
        ])
        let realRoom = LiveJSON.string(tLiveInfo["lProfileRoom"])
        return LiveRoomDetail(
            platform: .huya,
            roomId: realRoom.isEmpty ? roomId : realRoom,
            title: title,
            cover: LiveJSON.string(tLiveInfo["sScreenshot"]),
            userName: LiveJSON.string(tProfileInfo["sNick"]),
            userAvatar: LiveJSON.string(tProfileInfo["sAvatar180"]),
            online: LiveJSON.int(tLiveInfo["lTotalCount"]),
            isLive: LiveJSON.int(roomInfoMap["eLiveStatus"]) == 2,
            webURL: "https://www.huya.com/\(roomId)",
            introduction: LiveJSON.string(tLiveInfo["sIntroduction"]),
            playContextJSON: ctx
        )
    }

    func getPlayQualities(detail: LiveRoomDetail) async throws -> [LivePlayQuality] {
        let ctx = LiveJSON.decodeObject(detail.playContextJSON)
        let bitRates = LiveJSON.array(ctx["bitRates"]) ?? []
        return bitRates.enumerated().map { idx, item in
            LivePlayQuality(
                id: "huya-\(LiveJSON.int(item["bitRate"]))-\(idx)",
                name: LiveJSON.string(item["name"]),
                qn: LiveJSON.int(item["bitRate"]),
                bitRate: LiveJSON.int(item["bitRate"])
            )
        }
    }

    func getPlayURLs(detail: LiveRoomDetail, quality: LivePlayQuality) async throws -> LivePlayResult {
        let ctx = LiveJSON.decodeObject(detail.playContextJSON)
        let uid = LiveJSON.string(ctx["uid"]).isEmpty ? randomUid(length: 13) : LiveJSON.string(ctx["uid"])
        let lines = LiveJSON.array(ctx["lines"]) ?? []
        let bitRate = quality.bitRate ?? quality.qn
        var urls: [String] = []
        for line in lines {
            let base = LiveJSON.string(line["line"])
            let stream = LiveJSON.string(line["streamName"])
            let anti = LiveJSON.string(line["flvAntiCode"])
            guard !base.isEmpty, !stream.isEmpty, !anti.isEmpty else { continue }
            let params = processAnticode(anticode: anti, uid: uid, streamName: stream)
            var url = "\(base)/\(stream).flv?\(params)"
            if bitRate > 0 { url += "&ratio=\(bitRate)" }
            urls.append(url)
        }
        guard !urls.isEmpty else { throw NetworkError.message("虎牙无可用播放地址") }
        return LivePlayResult(urls: urls, headers: [
            "User-Agent": playUA,
            "Referer": "https://www.huya.com/"
        ])
    }

    // MARK: - Internals

    private func mapListItem(_ item: [String: Any]) -> LiveRoomItem? {
        let roomId = LiveJSON.string(item["profileRoom"])
        guard !roomId.isEmpty else { return nil }
        var cover = LiveJSON.string(item["screenshot"])
        if !cover.isEmpty, !cover.contains("?") {
            cover += "?x-oss-process=style/w338_h190&"
        }
        var title = LiveJSON.string(item["introduction"])
        if title.isEmpty { title = LiveJSON.string(item["roomName"]) }
        return LiveRoomItem(
            platform: .huya,
            roomId: roomId,
            title: title,
            cover: cover,
            userName: LiveJSON.string(item["nick"]),
            online: LiveJSON.int(item["totalCount"])
        )
    }

    private func getRoomInfo(_ roomId: String) async throws -> [String: Any] {
        let html = try await getText("https://m.huya.com/\(roomId)", query: [:], ua: mobileUA)
        guard let match = html.range(of: #"window\.HNF_GLOBAL_INIT\s*=\s*\{[\s\S]*?\}\s*;?\s*</script>"#, options: .regularExpression) else {
            throw NetworkError.message("虎牙页面结构变化，无法解析房间")
        }
        var jsonText = String(html[match])
        jsonText = jsonText.replacingOccurrences(of: #"window\.HNF_GLOBAL_INIT\s*="#, with: "", options: .regularExpression)
        jsonText = jsonText.replacingOccurrences(of: "</script>", with: "")
        jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasSuffix(";") { jsonText = String(jsonText.dropLast()) }
        // Strip inline functions that break JSON
        jsonText = jsonText.replacingOccurrences(
            of: #"function\s*\([^)]*\)\s*\{[\s\S]*?\}"#,
            with: "\"\"",
            options: .regularExpression
        )
        guard let data = jsonText.data(using: .utf8),
              var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("虎牙房间 JSON 解析失败")
        }
        let top = firstMatchInt(html, pattern: #"lChannelId":([0-9]+)"#)
        let sub = firstMatchInt(html, pattern: #"lSubChannelId":([0-9]+)"#)
        obj["topSid"] = top
        obj["subSid"] = sub
        return obj
    }

    private func processAnticode(anticode: String, uid: String, streamName: String) -> String {
        var query = [String: String]()
        for pair in anticode.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                query[parts[0]] = parts[1]
            }
        }
        query["t"] = "103"
        query["ctype"] = "tars_mobile"
        let wsTime = String(Int(Date().timeIntervalSince1970) + 21600, radix: 16)
        let seqId = "\(Int(Date().timeIntervalSince1970 * 1000) + (Int(uid) ?? 0))"
        let fmEncoded = query["fm"] ?? ""
        let fmDecoded = (fmEncoded.removingPercentEncoding ?? fmEncoded)
        let fmData = Data(base64Encoded: fmDecoded) ?? Data()
        let fm = String(data: fmData, encoding: .utf8) ?? ""
        let prefix = fm.split(separator: "_").first.map(String.init) ?? ""
        let ctype = query["ctype"] ?? "tars_mobile"
        let t = query["t"] ?? "103"
        let secretHash = LiveCryptoMD5.hex("\(seqId)|\(ctype)|\(t)")
        let wsSecret = LiveCryptoMD5.hex("\(prefix)_\(uid)_\(streamName)_\(secretHash)_\(wsTime)")
        let uuid = "\(Int.random(in: 1_000_000_000...4_000_000_000))"
        let out: [(String, String)] = [
            ("wsSecret", wsSecret),
            ("wsTime", wsTime),
            ("seqid", seqId),
            ("ctype", ctype),
            ("ver", "1"),
            ("fs", query["fs"] ?? ""),
            ("dMod", "mseh-0"),
            ("sdkPcdn", "1_1"),
            ("uid", uid),
            ("uuid", uuid),
            ("t", t),
            ("sv", "202411221719"),
            ("sdk_sid", "1732862566708"),
            ("a_block", "0")
        ]
        return out.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    private func randomUid(length: Int) -> String {
        let chars = Array("0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private func firstMatchInt(_ text: String, pattern: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return 0 }
        return Int(text[r]) ?? 0
    }

    private func getJSON(_ url: String, query: [String: String]) async throws -> [String: Any] {
        let text = try await getText(url, query: query)
        // cache.php sometimes returns JSON as string already, sometimes double-encoded
        if let data = text.data(using: .utf8) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            if let s = try? JSONSerialization.jsonObject(with: data) as? String,
               let d2 = s.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d2) as? [String: Any] {
                return obj
            }
        }
        throw NetworkError.message("虎牙 JSON 解析失败")
    }

    private func getText(_ url: String, query: [String: String], ua: String? = nil) async throws -> String {
        var comps = URLComponents(string: url)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let final = comps.url else { throw NetworkError.invalidURL }
        var req = URLRequest(url: final)
        req.timeoutInterval = 25
        req.setValue(ua ?? mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("https://m.huya.com/", forHTTPHeaderField: "Referer")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
