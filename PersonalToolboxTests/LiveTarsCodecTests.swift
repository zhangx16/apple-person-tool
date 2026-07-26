import XCTest
@testable import PersonalToolbox

final class LiveTarsCodecTests: XCTestCase {
    // MARK: - Normal round trip (make sure the crash fix didn't break real parsing)

    func testWriterReaderRoundTrip() {
        let w = LiveTars.Writer()
        w.writeInt64(1234, tag: 0)
        w.writeString("hello", tag: 1)
        w.writeBool(true, tag: 2)

        let r = LiveTars.Reader(w.buffer)
        XCTAssertEqual(r.readInt(tag: 0), 1234)
        XCTAssertEqual(r.readString(tag: 1), "hello")
        XCTAssertEqual(r.readInt(tag: 2), 1)
    }

    func testHuyaJoinAndHeartbeatPacketsAreNonEmpty() {
        let join = LiveTars.huyaJoinPacket(ayyuid: 1, tid: 2, sid: 3)
        XCTAssertFalse(join.isEmpty)
        XCTAssertFalse(LiveTars.huyaHeartbeat.isEmpty)
    }

    // MARK: - Crash regression: malformed/truncated buffers must degrade gracefully,
    // never trap. This is the exact bug class that crashed Huya danmaku on any push
    // packet whose shape didn't match what the reader expected.

    func testReadStringHandlesDeclaredLengthLongerThanBuffer() {
        // tag=1, type=.string1 (rawValue 6): head byte, then a length byte claiming
        // far more bytes than actually follow.
        var data = Data([UInt8((1 << 4) | 6)])
        data.append(200) // claims 200 bytes of string content
        data.append(contentsOf: [0x41, 0x42]) // only 2 bytes actually present

        let r = LiveTars.Reader(data)
        XCTAssertNil(r.readString(tag: 1))
    }

    func testReadStringHandlesString4LengthBeyondBuffer() {
        // tag=1, type=.string4 (rawValue 7): head byte, then a 4-byte big-endian
        // length with zero payload bytes following.
        var data = Data([UInt8((1 << 4) | 7)])
        data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // huge length, no payload

        let r = LiveTars.Reader(data)
        XCTAssertNil(r.readString(tag: 1))
    }

    func testReadIntHandlesTruncatedFixedWidthValue() {
        // tag=2, type=.int4 (rawValue 2): head byte, then only 2 of the required 4 bytes.
        var data = Data([UInt8((2 << 4) | 2)])
        data.append(contentsOf: [0x00, 0x01])

        let r = LiveTars.Reader(data)
        XCTAssertEqual(r.readInt(tag: 2, required: true), 0)
    }

    func testSkipFieldHandlesTruncatedSimpleList() {
        // A simpleList head followed immediately by EOF (no element-type byte, no size).
        let data = Data([UInt8((0 << 4) | 13)]) // tag=0, type=.simpleList
        let r = LiveTars.Reader(data)
        r.skipField() // must not crash
        XCTAssertTrue(r.isEOF)
    }

    func testParseHuyaPushOnGarbageDataReturnsEmpty() {
        let garbage = Data([0xFF, 0x00, 0x17, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x02])
        XCTAssertTrue(LiveTars.parseHuyaPush(garbage).isEmpty)
    }

    func testParseHuyaPushOnEmptyDataReturnsEmpty() {
        XCTAssertTrue(LiveTars.parseHuyaPush(Data()).isEmpty)
    }
}
