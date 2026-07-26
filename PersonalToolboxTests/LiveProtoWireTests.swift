import XCTest
@testable import PersonalToolbox

final class LiveProtoWireTests: XCTestCase {
    func testParseFieldsRoundTripsVarintAndString() {
        var data = LiveProtoWire.encodeVarintField(42, field: 1)
        data.append(LiveProtoWire.encodeString("hi", field: 2))

        let fields = LiveProtoWire.parseFields(data)

        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(fields.first(where: { $0.number == 1 })?.varint, 42)
        XCTAssertEqual(LiveProtoWire.stringField(fields, 2), "hi")
    }

    /// Regression test: a corrupted/adversarial length-delimited field can encode a
    /// varint length beyond Int.max. `Int(len64)` used to trap before the bounds check
    /// ever ran. This must now degrade gracefully instead of crashing the process.
    func testParseFieldsHandlesOversizedLengthWithoutCrashing() {
        var data = LiveProtoWire.encodeKey(field: 1, wire: 2)
        data.append(LiveProtoWire.encodeVarint(UInt64.max))
        // No payload bytes follow — this is exactly the truncated shape that used to trap.

        let fields = LiveProtoWire.parseFields(data)

        XCTAssertTrue(fields.isEmpty)
    }

    func testParseFieldsHandlesLengthLongerThanRemainingData() {
        var data = LiveProtoWire.encodeKey(field: 1, wire: 2)
        data.append(LiveProtoWire.encodeVarint(1000))
        data.append(contentsOf: [0x01, 0x02]) // far fewer bytes than the declared length

        let fields = LiveProtoWire.parseFields(data)

        XCTAssertTrue(fields.isEmpty)
    }

    func testParseFieldsOnEmptyData() {
        XCTAssertTrue(LiveProtoWire.parseFields(Data()).isEmpty)
    }
}
