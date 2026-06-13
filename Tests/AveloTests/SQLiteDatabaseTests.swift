import XCTest
@testable import Avelo

final class SQLiteDatabaseTests: XCTestCase {

    func testWriteResetsTransactionDepthAfterCommitFailure() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("PRAGMA foreign_keys = ON")
        try db.execute("""
            CREATE TABLE parent (
                id INTEGER PRIMARY KEY
            )
        """)
        try db.execute("""
            CREATE TABLE child (
                id INTEGER PRIMARY KEY,
                parent_id INTEGER,
                FOREIGN KEY(parent_id) REFERENCES parent(id) DEFERRABLE INITIALLY DEFERRED
            )
        """)

        do {
            try db.write { tx in
                try tx.execute("INSERT INTO child (id, parent_id) VALUES (1, 99)")
            }
            XCTFail("Expected commit to fail because of deferred foreign key violation")
        } catch {
            // Expected.
        }

        try db.write { tx in
            try tx.execute("INSERT INTO parent (id) VALUES (1)")
        }

        let parentCount = try db.queryOne("SELECT COUNT(*) FROM parent") { $0.int(0) } ?? 0
        XCTAssertEqual(parentCount, 1)
    }

    func testOptionalDateReturnsNilForMalformedValue() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (d TEXT)")
        try db.execute("INSERT INTO t (d) VALUES ('not-a-date')")

        let value = try db.queryOne("SELECT d FROM t") { row in
            row.optionalDate(0)
        } ?? nil
        XCTAssertNil(value)
    }

    func testTimestampThrowsForMalformedValue() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (ts TEXT)")
        try db.execute("INSERT INTO t (ts) VALUES ('not-a-timestamp')")

        do {
            _ = try db.queryOne("SELECT ts FROM t") { row in
                try row.timestamp(0)
            }
            XCTFail("Expected timestamp parsing to throw for malformed data")
        } catch {
            // Expected.
        }
    }

    func testPreparedStatementCacheIsBounded() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, value TEXT)")
        try db.execute("INSERT INTO t (id, value) VALUES (1, 'one')")

        for i in 0..<300 {
            let sql = "SELECT value FROM t WHERE id = \(i + 1)"
            _ = try db.queryOne(sql) { row in
                row.text(0)
            }
        }

        XCTAssertLessThanOrEqual(db.debugStatementCacheCount, 256)
    }

    func testBindFailuresReportDatabaseHandleMessage() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, value TEXT)")

        do {
            try db.execute("INSERT INTO t (id, value) VALUES (?, ?)", [.integer(1), .text("one"), .text("extra")])
            XCTFail("Expected bind failure for the extra placeholder binding")
        } catch {
            guard case AppError.database(.bindFailed(let message)) = error else {
                return XCTFail("Expected bindFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("index 3"))
            XCTAssertFalse(message.isEmpty)
        }
    }
}
