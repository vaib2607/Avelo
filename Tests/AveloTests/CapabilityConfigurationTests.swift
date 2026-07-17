import XCTest
@testable import Avelo

final class CapabilityConfigurationTests: XCTestCase {

    // MARK: - CompanyFeatureSet

    func testDefaultsEnableEverythingExceptInventory() {
        let set = CompanyFeatureSet.defaults
        XCTAssertFalse(set.inventory)
        XCTAssertTrue(set.billWise)
        XCTAssertTrue(set.cost)
        XCTAssertTrue(set.gst)
        XCTAssertTrue(set.payroll)
        XCTAssertTrue(set.banking)
        XCTAssertTrue(set.orders)
        XCTAssertTrue(set.batchesGodowns)
        XCTAssertTrue(set.manufacturing)
        XCTAssertTrue(set.budgets)
        XCTAssertTrue(set.interest)
    }

    func testFeatureSetDerivesInventoryFromCompanyRow() {
        XCTAssertTrue(CompanyFeatureSet(company: Company(name: "A", isInventoryEnabled: true)).inventory)
        XCTAssertFalse(CompanyFeatureSet(company: Company(name: "B", isInventoryEnabled: false)).inventory)
    }

    // MARK: - Router capability invalidation

    @MainActor
    func testLosingInventoryEvictsRouteSheetAndPendingReport() {
        let router = AppRouter()
        router.setFeatureSet(CompanyFeatureSet(inventory: true))
        router.go(.inventory)
        XCTAssertEqual(router.selection, .inventory)

        router.setFeatureSet(CompanyFeatureSet(inventory: false))
        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertNil(router.presentedSheet)
        XCTAssertNil(router.pendingReportSelection)
        XCTAssertFalse(router.isInventoryEnabled)
    }

    @MainActor
    func testCapabilityRevisionBumpsOnChangeAndResetButNotOnNoOp() {
        let router = AppRouter()
        let initial = router.capabilityRevision

        router.setFeatureSet(CompanyFeatureSet(inventory: true))
        XCTAssertEqual(router.capabilityRevision, initial + 1)

        router.setFeatureSet(CompanyFeatureSet(inventory: true))
        XCTAssertEqual(router.capabilityRevision, initial + 1, "Unchanged capabilities must not invalidate caches")

        router.reset()
        XCTAssertEqual(router.capabilityRevision, initial + 2)
    }

    @MainActor
    func testSetInventoryEnabledWrapperPreservesOtherFlags() {
        let router = AppRouter()
        router.setInventoryEnabled(true)
        XCTAssertTrue(router.featureSet.inventory)
        XCTAssertTrue(router.featureSet.payroll)
        router.setInventoryEnabled(false)
        XCTAssertFalse(router.featureSet.inventory)
        XCTAssertTrue(router.featureSet.gst)
    }

    // MARK: - WorkspaceConfiguration validation

    func testIdentifierValidationRejectsSQLishAndOversizedIdentifiers() {
        XCTAssertTrue(WorkspaceConfiguration.isValidIdentifier("voucher_date"))
        XCTAssertTrue(WorkspaceConfiguration.isValidIdentifier("amount.debit-2"))
        XCTAssertFalse(WorkspaceConfiguration.isValidIdentifier(""))
        XCTAssertFalse(WorkspaceConfiguration.isValidIdentifier("a b"))
        XCTAssertFalse(WorkspaceConfiguration.isValidIdentifier("x'; DROP TABLE avelo_vouchers;--"))
        XCTAssertFalse(WorkspaceConfiguration.isValidIdentifier(String(repeating: "a", count: 65)))
    }

    // MARK: - Repository

    func testSaveFindRoundTripAndUpsert() throws {
        let fixture = try TestCompany.make()
        let repository = WorkspaceConfigurationRepository(db: fixture.db)

        var configuration = WorkspaceConfiguration(
            density: .compact,
            columns: [.init(fieldId: "voucher_date", width: 120)],
            filters: [.init(fieldId: "narration", op: .contains, value: "rent")],
            groupingFieldIds: ["account_name"]
        )
        try repository.save(configuration, companyId: fixture.companyId, workspaceId: .vouchers)

        var loaded = try XCTUnwrap(repository.find(companyId: fixture.companyId, workspaceId: .vouchers))
        XCTAssertEqual(loaded, configuration)

        configuration.density = .comfortable
        try repository.save(configuration, companyId: fixture.companyId, workspaceId: .vouchers)
        loaded = try XCTUnwrap(repository.find(companyId: fixture.companyId, workspaceId: .vouchers))
        XCTAssertEqual(loaded.density, .comfortable)
    }

    func testConfigurationsAreCompanyScoped() throws {
        let fixture = try TestCompany.make()
        let repository = WorkspaceConfigurationRepository(db: fixture.db)
        try repository.save(WorkspaceConfiguration(), companyId: fixture.companyId, workspaceId: .accounts)

        XCTAssertNil(try repository.find(companyId: UUID(), workspaceId: .accounts))
    }

    func testSaveRejectsInvalidFieldIdentifiers() throws {
        let fixture = try TestCompany.make()
        let repository = WorkspaceConfigurationRepository(db: fixture.db)
        let hostile = WorkspaceConfiguration(columns: [.init(fieldId: "x'; DROP TABLE avelo_vouchers;--")])

        XCTAssertThrowsError(try repository.save(hostile, companyId: fixture.companyId, workspaceId: .reports))
        XCTAssertNil(try repository.find(companyId: fixture.companyId, workspaceId: .reports))
    }

    func testFindIgnoresNewerFormatVersionsAndCorruptPayloads() throws {
        let fixture = try TestCompany.make()
        let repository = WorkspaceConfigurationRepository(db: fixture.db)
        let now = DateFormatters.formatIsoTimestamp(Date())

        try fixture.db.execute(
            """
            INSERT INTO avelo_workspace_configurations
            (id, company_id, workspace_id, format_version, payload_json, created_at, updated_at)
            VALUES (?, ?, 'reports', ?, '{"future":true}', ?, ?)
            """,
            [.text(UUID().uuidString), .text(fixture.companyId.uuidString),
             .integer(Int64(WorkspaceConfiguration.currentFormatVersion + 1)),
             .text(now), .text(now)]
        )
        XCTAssertNil(try repository.find(companyId: fixture.companyId, workspaceId: .reports), "Rows written by a newer app version must be ignored, not decoded")

        try fixture.db.execute(
            """
            INSERT INTO avelo_workspace_configurations
            (id, company_id, workspace_id, format_version, payload_json, created_at, updated_at)
            VALUES (?, ?, 'audit', 1, 'not json at all', ?, ?)
            """,
            [.text(UUID().uuidString), .text(fixture.companyId.uuidString), .text(now), .text(now)]
        )
        XCTAssertNil(try repository.find(companyId: fixture.companyId, workspaceId: .audit), "A corrupt saved view must never block opening its workspace")
    }

    func testForeignCompanyRowIsRejectedBySchema() throws {
        let fixture = try TestCompany.make()
        let now = DateFormatters.formatIsoTimestamp(Date())

        XCTAssertThrowsError(try fixture.db.execute(
            """
            INSERT INTO avelo_workspace_configurations
            (id, company_id, workspace_id, format_version, payload_json, created_at, updated_at)
            VALUES (?, ?, 'accounts', 1, '{}', ?, ?)
            """,
            [.text(UUID().uuidString), .text(UUID().uuidString), .text(now), .text(now)]
        ), "company_id must reference a real company")
    }

    func testDeleteRemovesOnlyTheNamedWorkspace() throws {
        let fixture = try TestCompany.make()
        let repository = WorkspaceConfigurationRepository(db: fixture.db)
        try repository.save(WorkspaceConfiguration(), companyId: fixture.companyId, workspaceId: .accounts)
        try repository.save(WorkspaceConfiguration(), companyId: fixture.companyId, workspaceId: .vouchers)

        try repository.delete(companyId: fixture.companyId, workspaceId: .accounts)

        XCTAssertNil(try repository.find(companyId: fixture.companyId, workspaceId: .accounts))
        XCTAssertNotNil(try repository.find(companyId: fixture.companyId, workspaceId: .vouchers))
    }
}
