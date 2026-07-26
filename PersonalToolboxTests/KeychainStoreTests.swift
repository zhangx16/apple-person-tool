import XCTest
@testable import PersonalToolbox

final class KeychainStoreTests: XCTestCase {
    private let key = "test.keychainStore.roundtrip"

    /// CI 模拟器上宿主 app 以 CODE_SIGNING_ALLOWED=NO 构建，Keychain 写入被系统
    /// 拒绝（errSecMissingEntitlement）。写入不可用时跳过，而不是报假失败。
    private func skipUnlessKeychainAvailable() throws {
        KeychainStore.set("probe", for: "test.keychainStore.probe")
        defer { KeychainStore.delete("test.keychainStore.probe") }
        if KeychainStore.get("test.keychainStore.probe") != "probe" {
            throw XCTSkip("Keychain 在未签名的模拟器环境不可用")
        }
    }

    override func tearDown() {
        KeychainStore.delete(key)
        super.tearDown()
    }

    func testSetThenGetReturnsSameValue() throws {
        try skipUnlessKeychainAvailable()
        KeychainStore.set("hello-世界", for: key)
        XCTAssertEqual(KeychainStore.get(key), "hello-世界")
    }

    func testSetOverwritesPreviousValue() throws {
        try skipUnlessKeychainAvailable()
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
