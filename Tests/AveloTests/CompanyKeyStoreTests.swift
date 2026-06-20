import XCTest
@testable import Avelo

final class CompanyKeyStoreTests: XCTestCase {
    func testInMemoryKeyStoreRoundTripsAndDeletesCompanyKey() throws {
        let store = InMemoryCompanyKeyStore()
        let companyId = UUID()
        let key = try store.generateKey()

        XCTAssertEqual(key.count, 32)
        XCTAssertNil(try store.retrieve(companyId: companyId))

        try store.store(key: key, companyId: companyId)
        XCTAssertEqual(try store.retrieve(companyId: companyId), key)

        try store.delete(companyId: companyId)
        XCTAssertNil(try store.retrieve(companyId: companyId))
    }

    func testRecoveryKeyCodecRoundTripsRawKey() throws {
        let key = Data((0..<32).map { UInt8($0) })
        let encoded = RecoveryKeyCodec.encode(key)
        XCTAssertTrue(encoded.contains("-"))
        XCTAssertEqual(try RecoveryKeyCodec.decode(encoded), key)
        XCTAssertEqual(try RecoveryKeyCodec.decode(encoded.lowercased().replacingOccurrences(of: "-", with: " ")), key)
    }
}
