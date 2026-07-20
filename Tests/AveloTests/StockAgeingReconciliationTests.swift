import XCTest
@testable import Avelo

/// Rev3 §4.6 report/export parity: proves `ReportService.stockAgeing`'s
/// on-hand quantity/value reconciles against an independent raw SQL sum
/// over `trn_inventory_compat` — the same authoritative-SQL-vs-live pattern
/// already used for stock valuation (`StockValuationReconciliationTests`),
/// applied to the ageing report's own (separately written) aggregation
/// query so a column/join drift between the two reports would be caught.
final class StockAgeingReconciliationTests: XCTestCase {

    func testOnHandQuantityAndValueReconcileToRawTrnInventorySum() throws {
        let tc = try TestCompany.make()
        let inventory = InventoryService(db: tc.db, companyId: tc.companyId)
        let item = try inventory.createItem(code: "AGE-1", name: "Ageing Item", unit: "NOS")

        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-04-01")!, type: .stockIn, quantity: 10, ratePaise: 100)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-05-15")!, type: .stockIn, quantity: 5, ratePaise: 120)
        try inventory.recordMovement(itemId: item.id, date: DateFormatters.parseDate("2024-06-01")!, type: .stockOut, quantity: 4, ratePaise: 999)

        let asOf = DateFormatters.parseDate("2024-06-30")!
        let report = try ReportService(db: tc.db, companyId: tc.companyId).stockAgeing(asOfDate: asOf)
        let row = try XCTUnwrap(report.rows.first(where: { $0.itemCode == "AGE-1" }))

        let rawOnHand = try XCTUnwrap(tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE
                WHEN movement_type = 'in' THEN quantity
                WHEN movement_type = 'out' THEN -quantity
                WHEN movement_type = 'adjustment' THEN quantity
                ELSE 0 END), 0)
            FROM trn_inventory_compat
            WHERE company_id = ? AND item_id = ? AND date <= ?
            """,
            bind: [.text(tc.companyId.uuidString), .text(item.id.uuidString), .date(asOf)]
        ) { $0.int(0) })

        let rawValue = try XCTUnwrap(tc.db.queryOne(
            """
            SELECT COALESCE(SUM(CASE
                WHEN movement_type = 'in' THEN total_value_paise
                WHEN movement_type = 'out' THEN -total_value_paise
                ELSE 0 END), 0)
            FROM trn_inventory_compat
            WHERE company_id = ? AND item_id = ? AND date <= ?
            """,
            bind: [.text(tc.companyId.uuidString), .text(item.id.uuidString), .date(asOf)]
        ) { $0.int(0) })

        XCTAssertEqual(row.onHandQty, rawOnHand, "Reported on-hand quantity must reconcile to the raw canonical movement ledger")
        XCTAssertEqual(row.onHandValuePaise, rawValue, "Reported on-hand value must reconcile to the raw canonical movement ledger")
        XCTAssertEqual(row.onHandQty, 11, "10 + 5 - 4")
    }
}
