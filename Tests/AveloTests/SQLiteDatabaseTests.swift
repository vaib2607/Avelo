import XCTest
@testable import Avelo

final class SQLiteDatabaseTests: XCTestCase {

    func testFileBackedDatabaseIsEncryptedAtRestAndReopensWithRawKey() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("avelo-sqlcipher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("encrypted.sqlite")

        let key = Data((0..<32).map { UInt8($0) })

        do {
            let db = try SQLiteDatabase(path: url.path, key: key)
            defer { db.close() }
            try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
            try db.execute("INSERT INTO t (value) VALUES (?)", [.text("sealed")])
        }

        let header = try Data(contentsOf: url).prefix(16)
        XCTAssertNotEqual(String(data: header, encoding: .utf8), "SQLite format 3\u{0}")

        let reopened = try SQLiteDatabase(path: url.path, key: key)
        defer { reopened.close() }
        let value = try reopened.queryOne("SELECT value FROM t WHERE id = 1") { $0.text(0) }
        XCTAssertEqual(value, "sealed")
    }

    func testEncryptedDatabaseRejectsWrongPassphrase() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("avelo-sqlcipher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("encrypted.sqlite")

        let correct = Data(repeating: 1, count: 32)
        let wrong = Data(repeating: 2, count: 32)
        let db = try SQLiteDatabase(path: url.path, key: correct)
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
        db.close()

        do {
            _ = try SQLiteDatabase(path: url.path, key: wrong)
            XCTFail("Expected wrong passphrase to fail")
        } catch {
            guard case AppError.database(.wrongEncryptionKey(let message)) = error else {
                return XCTFail("Expected wrongEncryptionKey, got \(error)")
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("key rejected"))
        }
    }

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

    // AVL-P0-017: cache eviction must never finalize a statement that is
    // still busy (mid-iteration) in an outer stack frame. A nested/recursive
    // read using many distinct statements can push the cache well past its
    // bound while an outer cursor is paused inside its row callback; the
    // outer statement's `lastUsedAt` is the oldest in the cache at that
    // point, so it is the naive LRU eviction candidate. Evicting it would
    // finalize a statement `sqlite3_step` is still iterating.
    func testStatementCacheEvictionNeverFinalizesABusyOuterStatement() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, value TEXT)")
        for i in 0..<5 {
            try db.execute("INSERT INTO t (id, value) VALUES (\(i + 1), 'row\(i + 1)')")
        }

        var outerRows: [String] = []
        _ = try db.query("SELECT id, value FROM t ORDER BY id") { row in
            // While this outer statement is busy (stepping mid-iteration),
            // force eviction pressure with 300 distinct nested statements --
            // more than `maxCachedStatements` -- so the outer statement would
            // have been the oldest (and previously eligible) eviction victim.
            if outerRows.isEmpty {
                for i in 0..<300 {
                    let sql = "SELECT value FROM t WHERE id = \((i % 5) + 1)"
                    _ = try db.queryOne(sql) { $0.text(0) }
                }
            }
            outerRows.append(row.text(1))
        }

        XCTAssertEqual(outerRows, ["row1", "row2", "row3", "row4", "row5"])
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

    func testUserVersionThrowsWhenDatabaseHandleIsClosed() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        db.close()

        XCTAssertThrowsError(try db.userVersion()) { error in
            guard case AppError.database(let dbError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            switch dbError {
            case .openFailed(let message), .prepareFailed(let message):
                XCTAssertFalse(message.isEmpty)
            default:
                XCTFail("Expected openFailed or prepareFailed, got \(dbError)")
            }
        }
    }

    func testOpeningCorruptDatabaseBytesFailsClosedInsteadOfFallingBackToSchemaZero() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("avelo-sqlite-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("corrupt.sqlite")
        try Data("not-a-sqlite-database".utf8).write(to: url)

        XCTAssertThrowsError(try SQLiteDatabase(path: url.path)) { error in
            guard case AppError.database(let dbError) = error else {
                return XCTFail("Expected database error, got \(error)")
            }
            switch dbError {
            case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message), .execFailed(let message):
                XCTAssertFalse(message.isEmpty)
            default:
                XCTFail("Expected openFailed, prepareFailed, stepFailed, or execFailed, got \(dbError)")
            }
        }
    }
}
