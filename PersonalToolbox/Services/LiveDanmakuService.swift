import Foundation
import Compression

/// Live chat: Bilibili / Douyu / Huya / Douyin (SimpleLive protocols).
@MainActor
final class LiveDanmakuService: ObservableObject {
    @Published private(set) var messages: [LiveChatMessage] = []
    @Published private(set) var statusText: String = ""
    @Published var isEnabled: Bool = true

    private var task: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let maxMessages = 80
    private var heartbeatInterval: UInt64 = 30_000_000_000

    func start(platform: LivePlatform, danmakuJSON: String, roomId: String) {
        stop()
        guard isEnabled else {
            statusText = "弹幕已关闭"
            return
        }
        let ctx = LiveJSON.decodeObject(danmakuJSON)
        switch platform {
        case .bilibili:
            guard !LiveJSON.string(ctx["token"]).isEmpty else {
                statusText = "无弹幕 token"
                return
            }
            connectBilibili(ctx: ctx)
        case .douyu:
            connectDouyu(roomId: LiveJSON.string(ctx["roomId"]).ifEmpty(roomId))
        case .huya:
            connectHuya(ctx: ctx)
        case .douyin:
            Task { await connectDouyin(ctx: ctx, webRid: roomId) }
        case .kuaishou:
            statusText = "快手弹幕暂未接入"
        }
    }

    func stop() {
        heartbeat?.cancel()
        heartbeat = nil
        task?.cancel()
        task = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        messages = []
        statusText = ""
    }

    // MARK: - Bilibili

    private func connectBilibili(ctx: [String: Any]) {
        let host = LiveJSON.string(ctx["serverHost"]).ifEmpty("broadcastlv.chat.bilibili.com")
        let token = LiveJSON.string(ctx["token"])
        let roomId = LiveJSON.int(ctx["roomId"])
        let buvid = LiveJSON.string(ctx["buvid"])
        let cookie = LiveJSON.string(ctx["cookie"])
        guard let url = URL(string: "wss://\(host)/sub") else {
            statusText = "弹幕地址无效"
            return
        }
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)
        var req = URLRequest(url: url)
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let ws = session!.webSocketTask(with: req)
        webSocket = ws
        ws.resume()
        statusText = "弹幕连接中…"

        // Join room (op=7)
        let join: [String: Any] = [
            "uid": LiveJSON.int(ctx["uid"]),
            "roomid": roomId,
            "protover": 3,
            "buvid": buvid,
            "platform": "web",
            "type": 2,
            "key": token
        ]
        if let data = try? JSONSerialization.data(withJSONObject: join),
           let str = String(data: data, encoding: .utf8) {
            sendBinary(encodeBiliPacket(body: Data(str.utf8), operation: 7))
        }

        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.sendBinary(self?.encodeBiliPacket(body: Data(), operation: 2) ?? Data())
            }
        }
        task = Task { [weak self] in
            await self?.receiveLoopBili()
        }
        statusText = "弹幕已连接"
    }

    private func receiveLoopBili() async {
        while !Task.isCancelled {
            guard let ws = webSocket else { break }
            do {
                let msg = try await ws.receive()
                switch msg {
                case .data(let data):
                    handleBiliPacket(data)
                case .string(let s):
                    handleBiliPacket(Data(s.utf8))
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    statusText = "弹幕断开"
                }
                break
            }
        }
    }

    private func handleBiliPacket(_ data: Data) {
        guard data.count >= 16 else { return }
        let protocolVersion = readInt(data, offset: 6, length: 2)
        let operation = readInt(data, offset: 8, length: 4)
        var body = data.subdata(in: 16..<data.count)
        if operation == 5 {
            if protocolVersion == 2 {
                body = zlibInflate(body) ?? body
            } else if protocolVersion == 3 {
                body = brotliDecompress(body) ?? body
            }
            // May contain multiple frames
            parseBiliBodies(body)
        }
    }

    private func parseBiliBodies(_ data: Data) {
        // Split concatenated packets or JSON fragments
        var offset = 0
        if data.count >= 16 {
            while offset + 16 <= data.count {
                let packetLen = readInt(data, offset: offset, length: 4)
                if packetLen < 16 || offset + packetLen > data.count {
                    break
                }
                let op = readInt(data, offset: offset + 8, length: 4)
                let ver = readInt(data, offset: offset + 6, length: 2)
                var body = data.subdata(in: (offset + 16)..<(offset + packetLen))
                if op == 5 {
                    if ver == 2 { body = zlibInflate(body) ?? body }
                    if ver == 3 { body = brotliDecompress(body) ?? body }
                    emitBiliJSON(from: body)
                }
                offset += packetLen
            }
        }
        if offset == 0 {
            emitBiliJSON(from: data)
        }
    }

    private func emitBiliJSON(from body: Data) {
        guard let text = String(data: body, encoding: .utf8) else { return }
        // Split on control chars between JSON objects
        let parts = text.components(separatedBy: CharacterSet.controlCharacters)
        for part in parts where part.count > 2 && part.hasPrefix("{") {
            guard let d = part.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            let cmd = LiveJSON.string(obj["cmd"])
            guard cmd.contains("DANMU_MSG"),
                  let info = obj["info"] as? [Any],
                  info.count > 2 else { continue }
            let message = LiveJSON.string(info[1])
            var username = ""
            var color: UInt32 = 0xFFFFFF
            if let meta = info[0] as? [Any], meta.count > 3 {
                color = UInt32(LiveJSON.int(meta[3]))
                if color == 0 { color = 0xFFFFFF }
            }
            if let user = info[2] as? [Any], user.count > 1 {
                username = LiveJSON.string(user[1])
            }
            append(LiveChatMessage(userName: username, text: message, colorHex: color))
        }
    }

    private func encodeBiliPacket(body: Data, operation: Int) -> Data {
        var data = Data()
        let length = body.count + 16
        data.append(bigEndian32(length))
        data.append(bigEndian16(16))
        data.append(bigEndian16(0)) // protocol version for send
        data.append(bigEndian32(operation))
        data.append(bigEndian32(1))
        data.append(body)
        return data
    }

    // MARK: - Douyu

    private func connectDouyu(roomId: String) {
        guard let url = URL(string: "wss://danmuproxy.douyu.com:8506") else { return }
        session = URLSession(configuration: .default)
        let ws = session!.webSocketTask(with: url)
        webSocket = ws
        ws.resume()
        statusText = "弹幕连接中…"
        sendBinary(serializeDouyu("type@=loginreq/roomid@=\(roomId)/"))
        sendBinary(serializeDouyu("type@=joingroup/rid@=\(roomId)/gid@=-9999/"))
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                self?.sendBinary(self?.serializeDouyu("type@=mrkl/") ?? Data())
            }
        }
        task = Task { [weak self] in
            await self?.receiveLoopDouyu()
        }
        statusText = "弹幕已连接"
    }

    private func receiveLoopDouyu() async {
        while !Task.isCancelled {
            guard let ws = webSocket else { break }
            do {
                let msg = try await ws.receive()
                switch msg {
                case .data(let data):
                    handleDouyu(data)
                case .string(let s):
                    handleDouyu(Data(s.utf8))
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled { statusText = "弹幕断开" }
                break
            }
        }
    }

    private func handleDouyu(_ data: Data) {
        guard let body = deserializeDouyu(data) else { return }
        let obj = sttToDict(body)
        guard LiveJSON.string(obj["type"]) == "chatmsg" else { return }
        // Filter weird empty dms
        if obj["dms"] == nil { return }
        let col = LiveJSON.int(obj["col"])
        let color: UInt32
        switch col {
        case 1: color = 0xFF0000
        case 2: color = 0x1E87F0
        case 3: color = 0x7AC84B
        case 4: color = 0xFF7F00
        case 5: color = 0x9B39F4
        case 6: color = 0xFF69B4
        default: color = 0xFFFFFF
        }
        append(LiveChatMessage(
            userName: LiveJSON.string(obj["nn"]),
            text: LiveJSON.string(obj["txt"]),
            colorHex: color
        ))
    }

    private func serializeDouyu(_ body: String) -> Data {
        let payload = Array(body.utf8)
        let len = 4 + 4 + payload.count + 1
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt32(len).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(len).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(689).littleEndian) { Array($0) })
        data.append(0) // encrypted
        data.append(0) // reserved
        data.append(contentsOf: payload)
        data.append(0)
        return data
    }

    private func deserializeDouyu(_ buffer: Data) -> String? {
        guard buffer.count >= 12 else { return nil }
        let full = buffer.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let bodyLen = Int(full) - 9
        guard bodyLen > 0, buffer.count >= 12 + bodyLen else { return nil }
        let body = buffer.subdata(in: 12..<(12 + bodyLen))
        return String(data: body, encoding: .utf8)
    }

    private func sttToDict(_ str: String) -> [String: Any] {
        var result: [String: Any] = [:]
        for field in str.split(separator: "/") {
            if field.isEmpty { continue }
            let tokens = field.split(separator: "=", maxSplits: 1).map(String.init)
            guard tokens.count == 2 else { continue }
            let k = tokens[0].replacingOccurrences(of: "@", with: "")
            // tokens like type@=chatmsg
            let keyParts = field.split(separator: "@=", maxSplits: 1).map(String.init)
            if keyParts.count == 2 {
                let key = keyParts[0]
                let val = keyParts[1]
                    .replacingOccurrences(of: "@S", with: "/")
                    .replacingOccurrences(of: "@A", with: "@")
                result[key] = val
            } else if tokens.count == 2 {
                result[k] = tokens[1]
            }
        }
        // Prefer robust split
        result = [:]
        for field in str.split(separator: "/") where !field.isEmpty {
            let parts = field.split(separator: "@=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let val = String(parts[1])
                    .replacingOccurrences(of: "@S", with: "/")
                    .replacingOccurrences(of: "@A", with: "@")
                result[key] = val
            }
        }
        return result
    }

    // MARK: - Huya

    private func connectHuya(ctx: [String: Any]) {
        let ayyuid = Int64(LiveJSON.int(ctx["ayyuid"]))
        let topSid = Int64(LiveJSON.int(ctx["topSid"]))
        let subSid = Int64(LiveJSON.int(ctx["subSid"]))
        guard ayyuid > 0 || topSid > 0 else {
            statusText = "无虎牙弹幕参数"
            return
        }
        guard let url = URL(string: "wss://cdnws.api.huya.com") else { return }
        session = URLSession(configuration: .default)
        let ws = session!.webSocketTask(with: url)
        webSocket = ws
        ws.resume()
        statusText = "弹幕连接中…"
        let tid = topSid > 0 ? topSid : subSid
        let sid = subSid > 0 ? subSid : topSid
        sendBinary(LiveTars.huyaJoinPacket(ayyuid: ayyuid, tid: tid, sid: sid))
        heartbeatInterval = 60_000_000_000
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                self?.sendBinary(LiveTars.huyaHeartbeat)
            }
        }
        task = Task { [weak self] in
            await self?.receiveLoopHuya()
        }
        statusText = "弹幕已连接"
    }

    private func receiveLoopHuya() async {
        while !Task.isCancelled {
            guard let ws = webSocket else { break }
            do {
                let msg = try await ws.receive()
                switch msg {
                case .data(let data):
                    for chat in LiveTars.parseHuyaPush(data) {
                        append(LiveChatMessage(userName: chat.userName, text: chat.content, colorHex: chat.color))
                    }
                case .string(let s):
                    for chat in LiveTars.parseHuyaPush(Data(s.utf8)) {
                        append(LiveChatMessage(userName: chat.userName, text: chat.content, colorHex: chat.color))
                    }
                @unknown default: break
                }
            } catch {
                if !Task.isCancelled { statusText = "弹幕断开" }
                break
            }
        }
    }

    // MARK: - Douyin

    private func connectDouyin(ctx: [String: Any], webRid: String) async {
        let roomId = LiveJSON.string(ctx["roomId"]).ifEmpty(webRid)
        let userId = LiveJSON.string(ctx["userId"]).ifEmpty(randomDigits(12))
        var cookie = LiveJSON.string(ctx["cookie"])
        if cookie.isEmpty {
            cookie = "ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511"
        }
        let ua =
            "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400"
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        var comps = URLComponents(string: "wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/")!
        comps.queryItems = [
            URLQueryItem(name: "app_name", value: "douyin_web"),
            URLQueryItem(name: "version_code", value: "180800"),
            URLQueryItem(name: "webcast_sdk_version", value: "1.3.0"),
            URLQueryItem(name: "update_version_code", value: "1.3.0"),
            URLQueryItem(name: "compress", value: "gzip"),
            URLQueryItem(name: "cursor", value: "h-1_t-\(ts)_r-1_d-1_u-1"),
            URLQueryItem(name: "host", value: "https://live.douyin.com"),
            URLQueryItem(name: "aid", value: "6383"),
            URLQueryItem(name: "live_id", value: "1"),
            URLQueryItem(name: "did_rule", value: "3"),
            URLQueryItem(name: "debug", value: "false"),
            URLQueryItem(name: "maxCacheMessageNumber", value: "20"),
            URLQueryItem(name: "endpoint", value: "live_pc"),
            URLQueryItem(name: "support_wrds", value: "1"),
            URLQueryItem(name: "im_path", value: "/webcast/im/fetch/"),
            URLQueryItem(name: "user_unique_id", value: userId),
            URLQueryItem(name: "device_platform", value: "web"),
            URLQueryItem(name: "cookie_enabled", value: "true"),
            URLQueryItem(name: "screen_width", value: "1920"),
            URLQueryItem(name: "screen_height", value: "1080"),
            URLQueryItem(name: "browser_language", value: "zh-CN"),
            URLQueryItem(name: "browser_platform", value: "Win32"),
            URLQueryItem(name: "browser_name", value: "Mozilla"),
            URLQueryItem(name: "browser_version", value: ua.replacingOccurrences(of: "Mozilla/", with: "")),
            URLQueryItem(name: "browser_online", value: "true"),
            URLQueryItem(name: "tz_name", value: "Asia/Shanghai"),
            URLQueryItem(name: "identity", value: "audience"),
            URLQueryItem(name: "room_id", value: roomId),
            URLQueryItem(name: "heartbeatDuration", value: "0")
        ]
        var urlString = comps.url?.absoluteString ?? ""
        if let sig = try? LiveJSEngine.shared.douyinMSSDKSignature(roomId: roomId, userUniqueId: userId) {
            urlString += (urlString.contains("?") ? "&" : "?") + "signature=\(sig)"
        }
        guard let url = URL(string: urlString) else {
            statusText = "抖音弹幕地址无效"
            return
        }
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("https://live.douyin.com", forHTTPHeaderField: "Origin")
        req.setValue("https://live.douyin.com/\(webRid)", forHTTPHeaderField: "Referer")
        let ws = session!.webSocketTask(with: req)
        webSocket = ws
        ws.resume()
        statusText = "弹幕连接中…"
        // join = hb
        sendBinary(LiveProtoWire.pushFrame(payloadType: "hb"))
        heartbeatInterval = 10_000_000_000
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self?.sendBinary(LiveProtoWire.pushFrame(payloadType: "hb"))
            }
        }
        task = Task { [weak self] in
            await self?.receiveLoopDouyin()
        }
        statusText = "弹幕已连接"
    }

    private func receiveLoopDouyin() async {
        while !Task.isCancelled {
            guard let ws = webSocket else { break }
            do {
                let msg = try await ws.receive()
                let data: Data
                switch msg {
                case .data(let d): data = d
                case .string(let s): data = Data(s.utf8)
                @unknown default: continue
                }
                let decoded = LiveProtoWire.decodeDouyinChats(fromPushFrameData: data)
                if decoded.needAck {
                    let ackPayload = Data(decoded.internalExt.utf8)
                    sendBinary(LiveProtoWire.pushFrame(
                        payloadType: "ack",
                        logId: decoded.logId,
                        payload: ackPayload
                    ))
                }
                for chat in decoded.chats {
                    append(LiveChatMessage(userName: chat.userName, text: chat.content, colorHex: 0xFFFFFF))
                }
            } catch {
                if !Task.isCancelled { statusText = "弹幕断开" }
                break
            }
        }
    }

    private func randomDigits(_ n: Int) -> String {
        String((0..<n).map { _ in String(Int.random(in: 0...9)) }.joined())
    }

    // MARK: - Shared

    private func append(_ msg: LiveChatMessage) {
        messages.append(msg)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    private func sendBinary(_ data: Data) {
        webSocket?.send(.data(data)) { _ in }
    }

    private func readInt(_ data: Data, offset: Int, length: Int) -> Int {
        guard offset + length <= data.count else { return 0 }
        var value = 0
        for i in 0..<length {
            value = (value << 8) | Int(data[offset + i])
        }
        return value
    }

    private func bigEndian32(_ v: Int) -> Data {
        var be = UInt32(v).bigEndian
        return Data(bytes: &be, count: 4)
    }

    private func bigEndian16(_ v: Int) -> Data {
        var be = UInt16(v).bigEndian
        return Data(bytes: &be, count: 2)
    }

    private func zlibInflate(_ data: Data) -> Data? {
        // Strip zlib header if present and use Compression framework
        return data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            guard let base = src.baseAddress else { return nil }
            let dstSize = data.count * 8 + 4096
            var dst = Data(count: dstSize)
            let decoded = dst.withUnsafeMutableBytes { dstBuf -> Int in
                guard let dstBase = dstBuf.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self),
                    dstSize,
                    base.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            guard decoded > 0 else { return nil }
            dst.count = decoded
            return dst
        }
    }

    private func brotliDecompress(_ data: Data) -> Data? {
        // iOS Compression framework supports brotli from iOS 15+ as COMPRESSION_BROTLI
        return data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            guard let base = src.baseAddress else { return nil }
            let dstSize = max(data.count * 10, 64_000)
            var dst = Data(count: dstSize)
            let decoded = dst.withUnsafeMutableBytes { dstBuf -> Int in
                guard let dstBase = dstBuf.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self),
                    dstSize,
                    base.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_BROTLI
                )
            }
            guard decoded > 0 else { return nil }
            dst.count = decoded
            return dst
        }
    }
}

private extension String {
    func ifEmpty(_ alt: String) -> String { isEmpty ? alt : self }
}
