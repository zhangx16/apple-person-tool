import Foundation

/// Minimal Tars codec for Huya danmaku join / push parse (SimpleLive / real-url).
enum LiveTars {
    enum TagType: UInt8 {
        case int1 = 0
        case int2 = 1
        case int4 = 2
        case int8 = 3
        case float = 4
        case double = 5
        case string1 = 6
        case string4 = 7
        case map = 8
        case list = 9
        case structBegin = 10
        case structEnd = 11
        case zero = 12
        case simpleList = 13
    }

    // MARK: Writer

    final class Writer {
        private(set) var buffer = Data()

        func writeHead(tag: Int, type: TagType) {
            if tag < 15 {
                buffer.append(UInt8((tag << 4) | Int(type.rawValue)))
            } else {
                buffer.append(UInt8((15 << 4) | Int(type.rawValue)))
                buffer.append(UInt8(tag))
            }
        }

        func writeInt64(_ value: Int64, tag: Int) {
            if value == 0 {
                writeHead(tag: tag, type: .zero)
            } else if value >= Int8.min && value <= Int8.max {
                writeHead(tag: tag, type: .int1)
                buffer.append(UInt8(bitPattern: Int8(value)))
            } else if value >= Int16.min && value <= Int16.max {
                writeHead(tag: tag, type: .int2)
                var be = Int16(value).bigEndian
                buffer.append(Data(bytes: &be, count: 2))
            } else if value >= Int32.min && value <= Int32.max {
                writeHead(tag: tag, type: .int4)
                var be = Int32(value).bigEndian
                buffer.append(Data(bytes: &be, count: 4))
            } else {
                writeHead(tag: tag, type: .int8)
                var be = value.bigEndian
                buffer.append(Data(bytes: &be, count: 8))
            }
        }

        func writeInt32(_ value: Int32, tag: Int) {
            writeInt64(Int64(value), tag: tag)
        }

        func writeBool(_ value: Bool, tag: Int) {
            writeInt64(value ? 1 : 0, tag: tag)
        }

        func writeString(_ value: String, tag: Int) {
            let data = Data(value.utf8)
            if data.count > 255 {
                writeHead(tag: tag, type: .string4)
                var len = UInt32(data.count).bigEndian
                buffer.append(Data(bytes: &len, count: 4))
                buffer.append(data)
            } else {
                writeHead(tag: tag, type: .string1)
                buffer.append(UInt8(data.count))
                buffer.append(data)
            }
        }

        func writeBytes(_ data: Data, tag: Int) {
            writeHead(tag: tag, type: .simpleList)
            writeHead(tag: 0, type: .int1) // element type
            // length as int
            let len = data.count
            if len == 0 {
                writeHead(tag: 0, type: .zero)
            } else if len <= Int8.max {
                writeHead(tag: 0, type: .int1)
                buffer.append(UInt8(len))
            } else if len <= Int16.max {
                writeHead(tag: 0, type: .int2)
                var be = Int16(len).bigEndian
                buffer.append(Data(bytes: &be, count: 2))
            } else {
                writeHead(tag: 0, type: .int4)
                var be = Int32(len).bigEndian
                buffer.append(Data(bytes: &be, count: 4))
            }
            buffer.append(data)
        }
    }

    // MARK: Reader

    final class Reader {
        private let data: Data
        private var pos = 0

        init(_ data: Data) {
            self.data = data
        }

        var isEOF: Bool { pos >= data.count }

        func peekHead() -> (tag: Int, type: TagType)? {
            guard pos < data.count else { return nil }
            let b = data[pos]
            var tag = Int(b >> 4)
            let typeRaw = b & 0x0F
            if tag == 15 {
                guard pos + 1 < data.count else { return nil }
                tag = Int(data[pos + 1])
            }
            guard let type = TagType(rawValue: typeRaw) else { return nil }
            return (tag, type)
        }

        @discardableResult
        func skipHead() -> (tag: Int, type: TagType)? {
            guard pos < data.count else { return nil }
            let b = data[pos]
            pos += 1
            var tag = Int(b >> 4)
            let typeRaw = b & 0x0F
            if tag == 15 {
                guard pos < data.count else { return nil }
                tag = Int(data[pos])
                pos += 1
            }
            guard let type = TagType(rawValue: typeRaw) else { return nil }
            return (tag, type)
        }

        func skipField() {
            guard let head = skipHead() else { return }
            skipValue(type: head.type)
        }

        private func skipValue(type: TagType) {
            switch type {
            case .zero: break
            case .int1: pos += 1
            case .int2: pos += 2
            case .int4, .float: pos += 4
            case .int8, .double: pos += 8
            case .string1:
                guard pos < data.count else { return }
                let len = Int(data[pos]); pos += 1 + len
            case .string4:
                let len = Int(readUInt32BE()); pos += len
            case .structBegin:
                while let h = peekHead() {
                    if h.type == .structEnd {
                        _ = skipHead()
                        break
                    }
                    skipField()
                }
            case .structEnd: break
            case .map:
                // size tag 0
                let size = Int(forceReadNumber() ?? 0)
                for _ in 0..<(size * 2) { skipField() }
            case .list:
                let size = Int(forceReadNumber() ?? 0)
                for _ in 0..<size { skipField() }
            case .simpleList:
                _ = skipHead() // element type head
                let len = Int(forceReadNumber() ?? 0)
                pos = min(pos + max(len, 0), data.count)
            }
        }

        /// Read a number field at current position (any tag), used when size is next field.
        private func forceReadNumber() -> Int64? {
            guard let head = skipHead() else { return nil }
            switch head.type {
            case .zero: return 0
            case .int1:
                let v = Int8(bitPattern: data[pos]); pos += 1; return Int64(v)
            case .int2:
                let v = Int16(bigEndian: data.subdata(in: pos..<(pos+2)).withUnsafeBytes { $0.load(as: Int16.self) })
                pos += 2; return Int64(v)
            case .int4:
                let v = Int32(bigEndian: data.subdata(in: pos..<(pos+4)).withUnsafeBytes { $0.load(as: Int32.self) })
                pos += 4; return Int64(v)
            case .int8:
                let v = Int64(bigEndian: data.subdata(in: pos..<(pos+8)).withUnsafeBytes { $0.load(as: Int64.self) })
                pos += 8; return v
            default:
                skipValue(type: head.type)
                return 0
            }
        }

        func readInt(tag: Int, required: Bool = false) -> Int64? {
            guard let head = peekHead() else { return required ? 0 : nil }
            if head.tag != tag {
                return required ? 0 : nil
            }
            _ = skipHead()
            switch head.type {
            case .zero: return 0
            case .int1:
                let v = Int8(bitPattern: data[pos]); pos += 1; return Int64(v)
            case .int2:
                let v = Int16(bigEndian: data.subdata(in: pos..<(pos+2)).withUnsafeBytes { $0.load(as: Int16.self) })
                pos += 2; return Int64(v)
            case .int4:
                let v = Int32(bigEndian: data.subdata(in: pos..<(pos+4)).withUnsafeBytes { $0.load(as: Int32.self) })
                pos += 4; return Int64(v)
            case .int8:
                let v = Int64(bigEndian: data.subdata(in: pos..<(pos+8)).withUnsafeBytes { $0.load(as: Int64.self) })
                pos += 8; return v
            default:
                skipValue(type: head.type)
                return 0
            }
        }

        func readString(tag: Int) -> String? {
            guard let head = peekHead(), head.tag == tag else { return nil }
            _ = skipHead()
            switch head.type {
            case .string1:
                let len = Int(data[pos]); pos += 1
                let s = String(data: data.subdata(in: pos..<(pos+len)), encoding: .utf8)
                pos += len
                return s
            case .string4:
                let len = Int(readUInt32BE())
                let s = String(data: data.subdata(in: pos..<(pos+len)), encoding: .utf8)
                pos += len
                return s
            case .zero:
                return ""
            default:
                skipValue(type: head.type)
                return nil
            }
        }

        func readBytes(tag: Int) -> Data? {
            guard let head = peekHead(), head.tag == tag else { return nil }
            _ = skipHead()
            if head.type == .simpleList {
                _ = skipHead() // elem type
                let len = Int(readInt(tag: 0) ?? 0)
                guard pos + len <= data.count else { return nil }
                let d = data.subdata(in: pos..<(pos+len))
                pos += len
                return d
            }
            // sometimes as string
            if head.type == .string1 || head.type == .string4 {
                // re-read as string bytes - already consumed head
                return nil
            }
            skipValue(type: head.type)
            return nil
        }

        func readStruct(tag: Int) -> Reader? {
            guard let head = peekHead(), head.tag == tag else { return nil }
            _ = skipHead()
            if head.type == .structBegin {
                let start = pos
                // find matching end at same nesting - simple: read until structEnd at depth 0
                var depth = 1
                let begin = pos
                while pos < data.count && depth > 0 {
                    guard let h = skipHead() else { break }
                    if h.type == .structBegin {
                        depth += 1
                    } else if h.type == .structEnd {
                        depth -= 1
                    } else {
                        // undo and skip properly - messy
                        // Better approach: recursive skip
                        pos -= (h.tag >= 15 ? 2 : 1)
                        if h.type == .structEnd { break }
                        skipField()
                    }
                }
                _ = start
                // Simpler approach: use nested reader from begin to before end
                // Actually redo with proper skipValue
            }
            // Fallback: whole remaining as nested until we can parse fields by tag skip
            return nil
        }

        /// Read until finding tag, skipping earlier fields.
        func seekTag(_ tag: Int) -> Bool {
            while let head = peekHead() {
                if head.tag == tag { return true }
                if head.type == .structEnd { return false }
                skipField()
            }
            return false
        }

        private func readUInt32BE() -> UInt32 {
            let v = data.subdata(in: pos..<(pos+4)).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            pos += 4
            return v
        }
    }

    // MARK: Huya helpers

    static func huyaJoinPacket(ayyuid: Int64, tid: Int64, sid: Int64) -> Data {
        let oos = Writer()
        oos.writeInt64(ayyuid, tag: 0)
        oos.writeBool(true, tag: 1)
        oos.writeString("", tag: 2)
        oos.writeString("", tag: 3)
        oos.writeInt64(tid, tag: 4)
        oos.writeInt64(sid, tag: 5)
        oos.writeInt64(0, tag: 6)
        oos.writeInt64(0, tag: 7)

        let wscmd = Writer()
        wscmd.writeInt32(1, tag: 0)
        wscmd.writeBytes(oos.buffer, tag: 1)
        return wscmd.buffer
    }

    /// Heartbeat from SimpleLive: base64 ABQdAAwsNgBM
    static var huyaHeartbeat: Data {
        Data(base64Encoded: "ABQdAAwsNgBM") ?? Data()
    }

    struct HuyaChat {
        var userName: String
        var content: String
        var color: UInt32
    }

    static func parseHuyaPush(_ data: Data) -> [HuyaChat] {
        var results: [HuyaChat] = []
        let root = Reader(data)
        guard let type = root.readInt(tag: 0), type == 7 else { return results }
        guard let payload = root.readBytes(tag: 1) else { return results }
        // HYPushMessage: uri at tag 1, msg at tag 2
        let push = Reader(payload)
        _ = push.readInt(tag: 0) // pushType
        let uri = push.readInt(tag: 1) ?? 0
        guard uri == 1400, let msgBytes = push.readBytes(tag: 2) else { return results }

        // HYMessage: userInfo tag 0 (struct), content tag 3
        let msg = Reader(msgBytes)
        var nick = ""
        var content = ""
        var color: UInt32 = 0xFFFFFF

        // Parse fields by tag
        while let head = msg.peekHead() {
            if head.type == .structEnd { break }
            switch head.tag {
            case 0:
                // userInfo struct begin
                _ = msg.skipHead()
                if head.type == .structBegin {
                    let user = readStructBody(from: msg)
                    nick = user.nick
                } else {
                    msg.skipField()
                }
            case 3:
                content = msg.readString(tag: 3) ?? ""
            case 6:
                // bulletFormat struct
                _ = msg.skipHead()
                if head.type == .structBegin {
                    color = readBulletColor(from: msg)
                } else {
                    msg.skipField()
                }
            default:
                msg.skipField()
            }
        }
        if !content.isEmpty {
            results.append(HuyaChat(userName: nick, content: content, color: color == 0 ? 0xFFFFFF : color))
        }
        return results
    }

    private struct UserInfo { var nick: String = "" }

    private static func readStructBody(from msg: Reader) -> UserInfo {
        var info = UserInfo()
        while let head = msg.peekHead() {
            if head.type == .structEnd {
                _ = msg.skipHead()
                break
            }
            if head.tag == 2 {
                info.nick = msg.readString(tag: 2) ?? ""
            } else {
                msg.skipField()
            }
        }
        return info
    }

    private static func readBulletColor(from msg: Reader) -> UInt32 {
        var color: UInt32 = 0xFFFFFF
        while let head = msg.peekHead() {
            if head.type == .structEnd {
                _ = msg.skipHead()
                break
            }
            if head.tag == 0 {
                color = UInt32(msg.readInt(tag: 0) ?? 0xFFFFFF)
            } else {
                msg.skipField()
            }
        }
        return color
    }
}
