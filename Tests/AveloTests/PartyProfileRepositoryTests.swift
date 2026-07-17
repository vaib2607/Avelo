import XCTest
@testable import Avelo

final class PartyProfileRepositoryTests: XCTestCase {
    func testRoundTripsProfileAndLoadsEligibilityPolicy() throws {
        let fixture = try TestCompany.make()
        let repository = PartyProfileRepository(db: fixture.db)
        let profile = PartyProfile(
            accountId: fixture.customerId,
            companyId: fixture.companyId,
            usage: .both,
            creditLimitPaise: 125_000,
            defaultCreditPeriodDays: 30,
            maintainBillwise: true
        )

        try repository.upsert(profile)

        let loaded = try XCTUnwrap(repository.find(accountId: fixture.customerId, companyId: fixture.companyId))
        XCTAssertEqual(loaded.accountId, profile.accountId)
        XCTAssertEqual(loaded.companyId, profile.companyId)
        XCTAssertEqual(loaded.usage, .both)
        XCTAssertEqual(loaded.creditLimitPaise, 125_000)
        XCTAssertEqual(loaded.defaultCreditPeriodDays, 30)
        XCTAssertTrue(loaded.maintainBillwise)
        let company = try XCTUnwrap(CompanyRepository(db: fixture.db).findById(fixture.companyId))
        let account = try XCTUnwrap(AccountRepository(db: fixture.db).findById(fixture.customerId))
        let groups = try AccountGroupRepository(db: fixture.db).listForCompany(fixture.companyId)
        let policy = try AccountEligibilityPolicy.loading(db: fixture.db, companyId: fixture.companyId)
        XCTAssertTrue(policy.evaluate(account: account, for: .voucherParty(.purchase), company: company, groups: groups).isEligible)
    }

    func testRejectsCrossCompanyProfileAndNegativeCreditValues() throws {
        let fixture = try TestCompany.make()
        let otherCompanyId = UUID()
        let now = DateFormatters.formatIsoTimestamp(Date())
        try fixture.db.execute(
            "INSERT INTO avelo_companies (id, name, is_inventory_enabled, inventory_link_mode, created_at, updated_at) VALUES (?, ?, 1, 'manual', ?, ?)",
            [.text(otherCompanyId.uuidString), .text("Other"), .text(now), .text(now)]
        )

        XCTAssertThrowsError(try PartyProfileRepository(db: fixture.db).upsert(
            PartyProfile(accountId: fixture.customerId, companyId: otherCompanyId, usage: .customer)
        ))
        XCTAssertThrowsError(try PartyProfileRepository(db: fixture.db).upsert(
            PartyProfile(accountId: fixture.customerId, companyId: fixture.companyId, usage: .customer, creditLimitPaise: -1)
        ))
    }

    func testV23UpgradeCreatesPartyProfileSchemaAndOwnershipTriggers() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        let throughV23 = MigrationRunner.defaultMigrations.filter { $0.version.rawValue <= 23 }
        try MigrationRunner(migrations: throughV23).runMigrations(on: db)
        XCTAssertEqual(try db.userVersion(), 23)

        try MigrationRunner().runMigrations(on: db)

        XCTAssertEqual(try db.userVersion(), SchemaVersion.current.rawValue)
        let tableCount: Int64 = try db.queryOne(
            "SELECT COUNT(*) AS count FROM sqlite_master WHERE type = 'table' AND name = 'avelo_party_profiles'"
        ) { $0.int("count") } ?? 0
        let triggerCount: Int64 = try db.queryOne(
            "SELECT COUNT(*) AS count FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'trg_avelo_party_profiles_company_%'"
        ) { $0.int("count") } ?? 0
        XCTAssertEqual(tableCount, 1)
        XCTAssertEqual(triggerCount, 2)
    }
}
