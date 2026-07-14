import XCTest
@testable import Avelo

final class CompanyKeyStoreTests: XCTestCase {
    private let fixtureKey = Data((0..<32).map { UInt8($0) })
    private let canonicalFixture = "AV1-AAAQ-EAYE-AUDA-OCAJ-BIFQ-YDIO-B4IB-CEQT-CQKR-MFYY-DENB-WHA5-DYPQ-DOZWMC"
    private let legacyFixture = "AAAQ-EAYE-AUDA-OCAJ-BIFQ-YDIO-B4IB-CEQT-CQKR-MFYY-DENB-WHA5-DYPQ"

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

    func testRecoveryKeyCodecEmitsCanonicalAV1FixtureAndNormalizesInput() throws {
        XCTAssertEqual(RecoveryKeyCodec.encode(fixtureKey), canonicalFixture)
        XCTAssertEqual(try RecoveryKeyCodec.decode(canonicalFixture), fixtureKey)

        let relaxedInput = canonicalFixture
            .lowercased()
            .replacingOccurrences(of: "-", with: " \n")
        XCTAssertEqual(try RecoveryKeyCodec.decode(relaxedInput), fixtureKey)
        XCTAssertEqual(try RecoveryKeyCodec.canonicalize(relaxedInput), canonicalFixture)
    }

    func testRecoveryKeyCodecRejectsSingleCharacterPayloadMutation() throws {
        let typo = replacingPayloadCharacter(in: canonicalFixture, with: "B")

        XCTAssertThrowsError(try RecoveryKeyCodec.decode(typo)) { error in
            XCTAssertEqual(AppError.wrap(error), .recoveryKey(.checksumMismatch))
        }
    }

    func testRecoveryKeyCodecRejectsSingleCharacterChecksumMutation() throws {
        var typo = canonicalFixture
        let index = typo.index(before: typo.endIndex)
        typo.replaceSubrange(index...index, with: "A")

        XCTAssertThrowsError(try RecoveryKeyCodec.decode(typo)) { error in
            XCTAssertEqual(AppError.wrap(error), .recoveryKey(.checksumMismatch))
        }
    }

    func testRecoveryKeyCodecRejectsUnsupportedVersionAndMalformedPayload() throws {
        let unsupportedVersion = "AV2" + String(canonicalFixture.dropFirst(3))
        XCTAssertThrowsError(try RecoveryKeyCodec.decode(unsupportedVersion)) { error in
            XCTAssertEqual(AppError.wrap(error), .recoveryKey(.unsupportedVersion("AV2")))
        }

        let malformed = replacingPayloadCharacter(in: canonicalFixture, with: "0")
        XCTAssertThrowsError(try RecoveryKeyCodec.decode(malformed)) { error in
            XCTAssertEqual(AppError.wrap(error), .recoveryKey(.malformed))
        }
    }

    func testRecoveryKeyCodecAcceptsLegacyUnprefixedFixtureAndCanonicalizesIt() throws {
        XCTAssertEqual(try RecoveryKeyCodec.decode(legacyFixture), fixtureKey)
        XCTAssertEqual(try RecoveryKeyCodec.canonicalize(legacyFixture), canonicalFixture)
    }

    private func replacingPayloadCharacter(in key: String, with replacement: Character) -> String {
        var key = key
        let index = key.index(key.startIndex, offsetBy: 4)
        key.replaceSubrange(index...index, with: String(replacement))
        return key
    }
}
