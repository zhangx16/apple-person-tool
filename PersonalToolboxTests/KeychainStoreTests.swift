import XCTest
@testable import PersonalToolbox

final class KeychainStoreTests: XCTestCase {
    private let key = "test.keychainStore.roundtrip"

    override func tearDown() {
        KeychainStore.delete(key)
        super.tearDown()
    }

    func testSetThenGetReturnsSameValue() {
        KeychainStore.set("hello-世界", for: key)
        XCTAssertEqual(KeychainStore.get(key), "hello-世界")
    }

    func testSetOverwritesPreviousValue() {
        KeychainStore.set("first", for: key)
        KeychainStore.set("second", for: key)
        XCTAssertEqual(KeychainStore.get(key), "second")
    }

    func testDeleteRemovesValue() {
        KeychainStore.set("to-delete", for: key)
        KeychainStore.delete(key)
        XCTAssertNil(KeychainStore.get(key))
    }

    func testGetReturnsNilForMissingKey() {
        XCTAssertNil(KeychainStore.get("test.keychainStore.neverSet"))
    }
}
