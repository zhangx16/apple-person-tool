import Foundation
import Compression

/// Minimal protobuf wire codec for Douyin PushFrame / Response / ChatMessage.
enum LiveProtoWire {
    // MARK: Encode

    static func encodeVarint(_ value: UInt64) -> Data {
        var v = value
        var d = Data()
        while v > 0x7F {
            d.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        d.append(UInt8(v & 0x7F))
        return d
    }

    static func encodeKey(field: Int, wire: Int) -> Data {
        encodeVarint(UInt64(field << 3 | wire))
    }

    static func encodeString(_ s: String, field: Int) -> Data {
        let bytes = Data(s.utf8)
        var d = encodeKey(field: field, wire: 2)
        d.append(encodeVarint(UInt64(bytes.count)))
        d.append(bytes)
        return d
    }

    static func encodeBytes(_ b: Data, field: Int) -> Data {
        var d = encodeKey(field: field, wire: 2)
        d.append(encodeVarint(UInt64(b.count)))
        d.append(b)
        return d
    }

    static func encodeVarintField(_ v: UInt64, field: Int) -> Data {
        var d = encodeKey(field: field, wire: 0)
        d.append(encodeVarint(v))
        return d
    }

    /// PushFrame with payloadType only (hb / ack).
    static func pushFrame(payloadType: String, logId: UInt64 = 0, payload: Data = Data()) -> Data {
        var d = Data()
        if logId != 0 {
            d.append(encodeVarintField(logId, field: 2))
        }
        d.append(encodeString(payloadType, field: 7))
        if !payload.isEmpty {
            d.append(encodeBytes(payload, field: 8))
        }
        return d
    }

    // MARK: Decode

    struct Field {
        var number: Int
        var wire: Int
        var data: Data
        var varint: UInt64
    }

    static func parseFields(_ data: Data) -> [Field] {
        var fields: [Field] = []
        var i = 0
        while i < data.count {
            guard let (key, keyLen) = readVarint(data, at: i) else { break }
            i += keyLen
            let field = Int(key >> 3)
            let wire = Int(key & 0x7)
            switch wire {
            case 0:
                guard let (v, len) = readVarint(data, at: i) else { return fields }
                i += len
                fields.append(Field(number: field, wire: wire, data: Data(), varint: v))
            case 1:
                guard i + 8 <= data.count else { return fields }
                fields.append(Field(number: field, wire: wire, data: data.subdata(in: i..<(i+8)), varint: 0))
                i += 8
            case 2:
                guard let (len64, lenLen) = readVarint(data, at: i) else { return fields }
                i += lenLen
                let len = Int(len64)
                guard i + len <= data.count else { return fields }
                fields.append(Field(number: field, wire: wire, data: data.subdata(in: i..<(i+len)), varint: 0))
                i += len
            case 5:
                guard i + 4 <= data.count else { return fields }
                fields.append(Field(number: field, wire: wire, data: data.subdata(in: i..<(i+4)), varint: 0))
                i += 4
            default:
                return fields
            }
        }
        return fields
    }

    static func readVarint(_ data: Data, at start: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift = 0
        var i = start
        while i < data.count {
            let b = data[i]
            i += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 {
                return (result, i - start)
            }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    static func stringField(_ fields: [Field], _ n: Int) -> String? {
        fields.first(where: { $0.number == n && $0.wire == 2 }).flatMap { String(data: $0.data, encoding: .utf8) }
    }

    static func bytesField(_ fields: [Field], _ n: Int) -> Data? {
        fields.first(where: { $0.number == n && $0.wire == 2 })?.data
    }

    static func varintField(_ fields: [Field], _ n: Int) -> UInt64? {
        fields.first(where: { $0.number == n && $0.wire == 0 })?.varint
    }

    // MARK: Douyin message helpers

    struct PushFrame {
        var logId: UInt64
        var payloadType: String
        var payload: Data
        var payloadEncoding: String
    }

    static func decodePushFrame(_ data: Data) -> PushFrame? {
        let f = parseFields(data)
        return PushFrame(
            logId: varintField(f, 2) ?? 0,
            payloadType: stringField(f, 7) ?? "",
            payload: bytesField(f, 8) ?? Data(),
            payloadEncoding: stringField(f, 6) ?? ""
        )
    }

    struct Chat {
        var userName: String
        var content: String
    }

    /// Decode gzip'd Response and extract WebcastChatMessage texts.
    static func decodeDouyinChats(fromPushFrameData data: Data) -> (chats: [Chat], needAck: Bool, logId: UInt64, internalExt: String) {
        guard let frame = decodePushFrame(data) else {
            return ([], false, 0, "")
        }
        var payload = frame.payload
        // gzip decompress
        if frame.payloadEncoding == "gzip" || isGzip(payload) {
            payload = gunzip(payload) ?? payload
        }
        let resp = parseFields(payload)
        let needAck = (varintField(resp, 9) ?? 0) != 0
        let internalExt = stringField(resp, 5) ?? ""
        var chats: [Chat] = []
        // messagesList field 1 repeated Message
        for field in resp where field.number == 1 && field.wire == 2 {
            let msg = parseFields(field.data)
            let method = stringField(msg, 1) ?? ""
            guard method == "WebcastChatMessage", let chatPayload = bytesField(msg, 2) else { continue }
            if let chat = decodeChatMessage(chatPayload) {
                chats.append(chat)
            }
        }
        return (chats, needAck, frame.logId, internalExt)
    }

    static func decodeChatMessage(_ data: Data) -> Chat? {
        let f = parseFields(data)
        let content = stringField(f, 3) ?? ""
        var nick = ""
        // user field 2
        if let userData = bytesField(f, 2) {
            let u = parseFields(userData)
            nick = stringField(u, 3) ?? stringField(u, 2) ?? "" // nickName often field 3
        }
        if content.isEmpty && nick.isEmpty { return nil }
        return Chat(userName: nick, content: content)
    }

    private static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x1F && data[1] == 0x8B
    }

    private static func gunzip(_ data: Data) -> Data? {
        // Skip gzip header and use zlib inflate with window bits - Compression framework
        // For gzip: use compression_decode with COMPRESSION_ZLIB after stripping header is unreliable.
        // Use process via InputStream approach:
        return data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            guard let base = src.baseAddress else { return nil }
            // Try COMPRESSION_ZLIB on raw deflate after gzip header (10 bytes + optional FNAME)
            var offset = 10
            if data.count > 3 {
                let flags = data[3]
                if flags & 0x04 != 0, data.count > offset + 2 { // FEXTRA
                    let xlen = Int(data[offset]) | (Int(data[offset+1]) << 8)
                    offset += 2 + xlen
                }
                if flags & 0x08 != 0 { // FNAME
                    while offset < data.count && data[offset] != 0 { offset += 1 }
                    offset += 1
                }
                if flags & 0x10 != 0 { // FCOMMENT
                    while offset < data.count && data[offset] != 0 { offset += 1 }
                    offset += 1
                }
                if flags & 0x02 != 0 { offset += 2 } // FHCRC
            }
            guard offset < data.count else { return nil }
            // raw deflate stream (no zlib header) — use zlib with windowBits by prepending dummy zlib header
            // Apple Compression COMPRESSION_ZLIB expects zlib wrapper. Prepend 0x78 0x9C
            var deflate = Data([0x78, 0x9C])
            // exclude 8-byte gzip footer
            let end = max(offset, data.count - 8)
            guard end > offset else { return nil }
            deflate.append(data.subdata(in: offset..<end))
            let dstSize = deflate.count * 20 + 4096
            var dst = Data(count: dstSize)
            let n = dst.withUnsafeMutableBytes { dstBuf -> Int in
                guard let dstBase = dstBuf.baseAddress else { return 0 }
                return deflate.withUnsafeBytes { srcBuf -> Int in
                    guard let srcBase = srcBuf.baseAddress else { return 0 }
                    return compression_decode_buffer(
                        dstBase.assumingMemoryBound(to: UInt8.self),
                        dstSize,
                        srcBase.assumingMemoryBound(to: UInt8.self),
                        deflate.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            guard n > 0 else { return nil }
            dst.count = n
            return dst
        }
    }
}
