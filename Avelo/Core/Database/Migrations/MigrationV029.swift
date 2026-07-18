import Foundation

/// Extends fiscal-lock enforcement to the canonical V027 transaction tracks.
public struct MigrationV029: Migration {
    public let version: SchemaVersion = .v29
    public let description = "Enforce fiscal locks on canonical transaction tracks"

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        for sql in Self.triggerSQL {
            try db.execute(sql)
        }
    }

    static let triggerSQL = [
        """
        CREATE TRIGGER trg_trn_accounting_fy_locked_insert
        BEFORE INSERT ON trn_accounting
        WHEN (SELECT fy.is_locked FROM avelo_vouchers v JOIN avelo_financial_years fy ON fy.id = v.financial_year_id WHERE v.id = NEW.voucher_id) = 1
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked'); END;
        """,
        """
        CREATE TRIGGER trg_trn_accounting_fy_locked_update
        BEFORE UPDATE ON trn_accounting
        WHEN (SELECT fy.is_locked FROM avelo_vouchers v JOIN avelo_financial_years fy ON fy.id = v.financial_year_id WHERE v.id = OLD.voucher_id) = 1
          OR (SELECT fy.is_locked FROM avelo_vouchers v JOIN avelo_financial_years fy ON fy.id = v.financial_year_id WHERE v.id = NEW.voucher_id) = 1
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked'); END;
        """,
        """
        CREATE TRIGGER trg_trn_accounting_fy_locked_delete
        BEFORE DELETE ON trn_accounting
        WHEN (SELECT fy.is_locked FROM avelo_vouchers v JOIN avelo_financial_years fy ON fy.id = v.financial_year_id WHERE v.id = OLD.voucher_id) = 1
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked'); END;
        """,
        """
        CREATE TRIGGER trg_trn_inventory_fy_locked_insert
        BEFORE INSERT ON trn_inventory
        WHEN EXISTS (SELECT 1 FROM avelo_financial_years fy WHERE fy.company_id = NEW.company_id AND fy.is_locked = 1 AND NEW.date BETWEEN fy.start_date AND fy.end_date)
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked; stock movements are not allowed'); END;
        """,
        """
        CREATE TRIGGER trg_trn_inventory_fy_locked_update
        BEFORE UPDATE ON trn_inventory
        WHEN EXISTS (SELECT 1 FROM avelo_financial_years fy WHERE fy.company_id = OLD.company_id AND fy.is_locked = 1 AND OLD.date BETWEEN fy.start_date AND fy.end_date)
          OR EXISTS (SELECT 1 FROM avelo_financial_years fy WHERE fy.company_id = NEW.company_id AND fy.is_locked = 1 AND NEW.date BETWEEN fy.start_date AND fy.end_date)
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked; stock movement edits are not allowed'); END;
        """,
        """
        CREATE TRIGGER trg_trn_inventory_fy_locked_delete
        BEFORE DELETE ON trn_inventory
        WHEN EXISTS (SELECT 1 FROM avelo_financial_years fy WHERE fy.company_id = OLD.company_id AND fy.is_locked = 1 AND OLD.date BETWEEN fy.start_date AND fy.end_date)
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked; stock movement deletes are not allowed'); END;
        """,
        """
        CREATE TRIGGER trg_trn_inventory_cost_allocations_fy_locked_insert
        BEFORE INSERT ON trn_inventory_cost_allocations
        WHEN EXISTS (SELECT 1 FROM trn_accounting a JOIN avelo_vouchers v ON v.id = a.voucher_id JOIN avelo_financial_years fy ON fy.id = v.financial_year_id WHERE a.id = NEW.accounting_id AND fy.is_locked = 1)
          OR EXISTS (SELECT 1 FROM trn_inventory i JOIN avelo_financial_years fy ON fy.company_id = i.company_id AND i.date BETWEEN fy.start_date AND fy.end_date WHERE i.id = NEW.inventory_id AND fy.is_locked = 1)
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked'); END;
        """,
        """
        CREATE TRIGGER trg_trn_inventory_cost_allocations_fy_locked_update
        BEFORE UPDATE ON trn_inventory_cost_allocations
        WHEN EXISTS (SELECT 1 FROM trn_accounting a JOIN avelo_vouchers v ON v.id = a.voucher_id JOIN avelo_financial_years fy ON fy.id = v.financial_year_id WHERE a.id IN (OLD.accounting_id, NEW.accounting_id) AND fy.is_locked = 1)
          OR EXISTS (SELECT 1 FROM trn_inventory i JOIN avelo_financial_years fy ON fy.company_id = i.company_id AND i.date BETWEEN fy.start_date AND fy.end_date WHERE i.id IN (OLD.inventory_id, NEW.inventory_id) AND fy.is_locked = 1)
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked'); END;
        """,
        """
        CREATE TRIGGER trg_trn_inventory_cost_allocations_fy_locked_delete
        BEFORE DELETE ON trn_inventory_cost_allocations
        WHEN EXISTS (SELECT 1 FROM trn_accounting a JOIN avelo_vouchers v ON v.id = a.voucher_id JOIN avelo_financial_years fy ON fy.id = v.financial_year_id WHERE a.id = OLD.accounting_id AND fy.is_locked = 1)
          OR EXISTS (SELECT 1 FROM trn_inventory i JOIN avelo_financial_years fy ON fy.company_id = i.company_id AND i.date BETWEEN fy.start_date AND fy.end_date WHERE i.id = OLD.inventory_id AND fy.is_locked = 1)
        BEGIN SELECT RAISE(ABORT, 'Financial year is locked'); END;
        """
    ]

    static let triggerNames = [
        "trg_trn_accounting_fy_locked_insert", "trg_trn_accounting_fy_locked_update", "trg_trn_accounting_fy_locked_delete",
        "trg_trn_inventory_fy_locked_insert", "trg_trn_inventory_fy_locked_update", "trg_trn_inventory_fy_locked_delete",
        "trg_trn_inventory_cost_allocations_fy_locked_insert", "trg_trn_inventory_cost_allocations_fy_locked_update", "trg_trn_inventory_cost_allocations_fy_locked_delete"
    ]
}
