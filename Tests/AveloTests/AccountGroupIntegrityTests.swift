import XCTest
@testable import Avelo

final class AccountGroupIntegrityTests: XCTestCase {

    func testCreateGroupRejectsForeignParentWithoutPersistence() throws {
        let (db, companyA, companyB) = try makeSharedDatabase()
        let service = AccountService(db: db, companyId: companyA.companyId)

        XCTAssertThrowsError(
            try service.createGroup(
                code: "FOREIGN_PARENT",
                name: "Foreign Parent",
                nature: .assets,
                parentGroupId: companyB.assetsGroupId
            )
        ) { error in
            assertBusinessRule(error, contains: "same company")
        }

        XCTAssertFalse(try service.listGroups().contains { $0.code == "FOREIGN_PARENT" })
    }

    func testUpdateGroupRejectsForeignParentWithoutPersistence() throws {
        let (db, companyA, companyB) = try makeSharedDatabase()
        let service = AccountService(db: db, companyId: companyA.companyId)
        var group = try service.createGroup(code: "LOCAL_ASSET", name: "Local Asset", nature: .assets)
        group.parentGroupId = companyB.assetsGroupId

        XCTAssertThrowsError(try service.updateGroup(group)) { error in
            assertBusinessRule(error, contains: "same company")
        }

        XCTAssertNil(try XCTUnwrap(service.findGroup(group.id)).parentGroupId)
    }

    func testUpdateGroupRejectsIndirectCycleWithoutPersistence() throws {
        let tc = try TestCompany.make()
        let service = AccountService(db: tc.db, companyId: tc.companyId)
        var parent = try service.createGroup(code: "PARENT", name: "Parent", nature: .assets)
        let child = try service.createGroup(code: "CHILD", name: "Child", nature: .assets, parentGroupId: parent.id)
        parent.parentGroupId = child.id

        XCTAssertThrowsError(try service.updateGroup(parent)) { error in
            assertBusinessRule(error, contains: "descendant")
        }

        XCTAssertNil(try XCTUnwrap(service.findGroup(parent.id)).parentGroupId)
        XCTAssertEqual(try XCTUnwrap(service.findGroup(child.id)).parentGroupId, parent.id)
    }

    func testCreateGroupRejectsNatureMismatchWithoutPersistence() throws {
        let tc = try TestCompany.make()
        let service = AccountService(db: tc.db, companyId: tc.companyId)
        let parent = try service.createGroup(code: "ASSET_PARENT", name: "Asset Parent", nature: .assets)

        XCTAssertThrowsError(
            try service.createGroup(
                code: "LIABILITY_CHILD",
                name: "Liability Child",
                nature: .liabilities,
                parentGroupId: parent.id
            )
        ) { error in
            assertBusinessRule(error, contains: "same nature")
        }

        XCTAssertFalse(try service.listGroups().contains { $0.code == "LIABILITY_CHILD" })
    }

    func testUpdateGroupRejectsNatureChangeConflictingWithChildWithoutPersistence() throws {
        let tc = try TestCompany.make()
        let service = AccountService(db: tc.db, companyId: tc.companyId)
        var parent = try service.createGroup(code: "ASSET_PARENT", name: "Asset Parent", nature: .assets)
        _ = try service.createGroup(code: "ASSET_CHILD", name: "Asset Child", nature: .assets, parentGroupId: parent.id)
        parent.nature = .liabilities

        XCTAssertThrowsError(try service.updateGroup(parent)) { error in
            assertBusinessRule(error, contains: "same nature")
        }

        XCTAssertEqual(try XCTUnwrap(service.findGroup(parent.id)).nature, .assets)
    }

    func testSeedImportRejectsCycleBeforeWritingGroups() throws {
        let tc = try TestCompany.make()
        let before = try groupCount(in: tc.db, companyId: tc.companyId)
        let payload = DefaultChartOfAccountsPayload(
            groups: [
                .init(code: "IMPORT_PARENT", name: "Import Parent", nature: "assets", sortOrder: 1, under: "IMPORT_CHILD"),
                .init(code: "IMPORT_CHILD", name: "Import Child", nature: "assets", sortOrder: 2, under: "IMPORT_PARENT")
            ],
            ledgers: [],
            voucherTypes: []
        )

        XCTAssertThrowsError(
            try SeedLoader().load(payload, into: tc.db, companyId: tc.companyId, financialYearId: tc.fy.id)
        ) { error in
            assertBusinessRule(error, contains: "cycle")
        }

        XCTAssertEqual(try groupCount(in: tc.db, companyId: tc.companyId), before)
    }

    func testSeedImportRejectsNatureConflictBeforeWritingGroups() throws {
        let tc = try TestCompany.make()
        let before = try groupCount(in: tc.db, companyId: tc.companyId)
        let payload = DefaultChartOfAccountsPayload(
            groups: [
                .init(code: "IMPORT_PARENT", name: "Import Parent", nature: "assets", sortOrder: 1),
                .init(code: "IMPORT_CHILD", name: "Import Child", nature: "income", sortOrder: 2, under: "IMPORT_PARENT")
            ],
            ledgers: [],
            voucherTypes: []
        )

        XCTAssertThrowsError(
            try SeedLoader().load(payload, into: tc.db, companyId: tc.companyId, financialYearId: tc.fy.id)
        ) { error in
            assertBusinessRule(error, contains: "same nature")
        }

        XCTAssertEqual(try groupCount(in: tc.db, companyId: tc.companyId), before)
    }

    private func makeSharedDatabase() throws -> (SQLiteDatabase, TestCompany, TestCompany) {
        let db = try SQLiteDatabase(path: ":memory:")
        try MigrationRunner().runMigrations(on: db)
        let companyA = try TestCompany.seed(into: db, companyId: UUID(), companyName: "Company A")
        let companyB = try TestCompany.seed(into: db, companyId: UUID(), companyName: "Company B")
        return (db, companyA, companyB)
    }

    private func groupCount(in db: SQLiteDatabase, companyId: Company.ID) throws -> Int64 {
        try db.queryOne(
            "SELECT COUNT(*) FROM avelo_account_groups WHERE company_id = ?",
            bind: [.text(companyId.uuidString)]
        ) { $0.int(0) } ?? 0
    }

    private func assertBusinessRule(_ error: Error,
                                    contains expectedMessage: String,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        guard case AppError.businessRule(let message) = error else {
            return XCTFail("Expected businessRule, got \(error)", file: file, line: line)
        }
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains(expectedMessage),
            "Expected '\(message)' to contain '\(expectedMessage)'.",
            file: file,
            line: line
        )
    }
}
