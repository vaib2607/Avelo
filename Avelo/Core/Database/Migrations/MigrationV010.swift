import Foundation

public struct MigrationV010: Migration {

    public let version: SchemaVersion = .v10
    public let description: String = "Financial years: enforce non-overlap on updates as well as inserts."

    public init() {}

    public func up(_ db: SQLiteDatabase) throws {
        try db.execute("DROP TRIGGER IF EXISTS trg_avelo_fy_no_overlap_update")
        try db.execute(
            """
            CREATE TRIGGER trg_avelo_fy_no_overlap_update
            BEFORE UPDATE ON avelo_financial_years
            FOR EACH ROW
            BEGIN
                SELECT RAISE(ABORT, 'Financial year overlaps an existing year for this company')
                WHERE EXISTS (
                    SELECT 1 FROM avelo_financial_years fy
                    WHERE fy.company_id = NEW.company_id
                      AND fy.id <> OLD.id
                      AND NOT (NEW.end_date < fy.start_date OR NEW.start_date > fy.end_date)
                );
            END;
            """
        )
    }
}
