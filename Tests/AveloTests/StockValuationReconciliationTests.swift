import XCTest
@testable import Avelo

/// Rev3 §4.6/§4.7 (Phase 1.3): stock valuation is parity-critical after the
/// V027 migration to canonical `trn_inventory`. This does not re-derive FIFO/
/// weighted-average layer logic independently (that would just duplicate
/// `InventoryValuationEngine`) — it instead proves the aggregate net
/// quantity/value the report publishes reconciles against a raw SQL sum over
/// `trn_inventory`, the same "authoritative SQL vs live" pattern already used
/// for trial balance (`AccountTreeReconciliationTests`) and P&L
/// (`ProfitLossReconciliationTests`). This is the check that would catch a
/// post-migration read bug (wrong table/join/company filter silently
/// dropping or double-counting movements) that unit-level valuation-method
/// tests can't see.
final class StockValuationReconciliationTests: XCTestCase {

    func testFifoItemClosingQuantityAndValueMatchRawTrnInventorySum() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "FIFO-PARITY", name: "FIFO Parity", unit: "NOS", valuationMethod: .fifo)

        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 10, ratePaise: 100)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-02")!, type: .stockIn, quantity: 10, ratePaise: 200)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-03")!, type: .stockOut, quantity: 15, ratePaise: 999)

        try assertReportReconcilesToRawSql(tc: tc, itemId: item.id, itemCode: "FIFO-PARITY", asOf: "2024-06-30")
    }

    func testWeightedAverageItemClosingQuantityAndValueMatchRawTrnInventorySum() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "WAVG-PARITY", name: "WAVG Parity", unit: "NOS", valuationMethod: .weightedAverage)

        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockIn, quantity: 20, ratePaise: 100)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-05")!, type: .stockIn, quantity: 30, ratePaise: 150)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-10")!, type: .stockOut, quantity: 25, ratePaise: 999)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-15")!, type: .adjustment, quantity: 2, ratePaise: 999)

        try assertReportReconcilesToRawSql(tc: tc, itemId: item.id, itemCode: "WAVG-PARITY", asOf: "2024-06-30")
    }

    private func assertReportReconcilesToRawSql(tc: TestCompany, itemId: InventoryItem.ID, itemCode: String, asOf: String) throws {
        let report = try ReportService(db: tc.db, companyId: tc.companyId).stockValuation(
            asOfDate: DateFormatters.parseDate(asOf)!
        )
        let row = try XCTUnwrap(report.rows.first(where: { $0.itemCode == itemCode }))

        // Independent of any valuation-method replay logic: net signed
        // quantity/value is a plain sum over the canonical movement ledger.
        let rawNetQty = try XCTUnwrap(tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE
                WHEN movement_type = 'in' THEN quantity_numerator
                WHEN movement_type = 'out' THEN -quantity_numerator
                WHEN movement_type = 'adjustment' THEN quantity_numerator
                ELSE 0 END), 0)
            FROM trn_inventory
            WHERE company_id = ? AND stock_item_id = ? AND date <= ?
            """,
            bind: [.text(tc.companyId.uuidString), .text(itemId.uuidString), .date(DateFormatters.parseDate(asOf)!)]
        ) { $0.int(0) })

        let rawNetValue = try XCTUnwrap(tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE
                WHEN movement_type = 'in' THEN base_value_paise + landed_cost_paise
                WHEN movement_type = 'out' THEN -(base_value_paise + landed_cost_paise)
                WHEN movement_type = 'adjustment' THEN base_value_paise + landed_cost_paise
                ELSE 0 END), 0)
            FROM trn_inventory
            WHERE company_id = ? AND stock_item_id = ? AND date <= ?
            """,
            bind: [.text(tc.companyId.uuidString), .text(itemId.uuidString), .date(DateFormatters.parseDate(asOf)!)]
        ) { $0.int(0) })

        XCTAssertEqual(Int64(row.closingQty.numerator), Int64(rawNetQty),
                        "Report closing quantity must reconcile to the raw canonical movement ledger")
        XCTAssertEqual(row.closingValuePaise, rawNetValue,
                        "Report closing value must reconcile to the raw canonical movement ledger")
    }
}
