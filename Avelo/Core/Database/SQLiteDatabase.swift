import Foundation
import SQLite3

let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLValue: Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null

    public static func date(_ d: Date) -> SQLValue { .text(DateFormatters.formatIsoDate(d)) }
    public static func timestamp(_ d: Date) -> SQLValue { .text(DateFormatters.formatIsoTimestamp(d)) }
    public static func optionalText(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }
    public static func optionalInteger(_ i: Int64?) -> SQLValue { i.map { .integer($0) } ?? .null }
    public static func optionalReal(_ d: Double?) -> SQLValue { d.map { .real($0) } ?? .null }
    public static func optionalDate(_ d: Date?) -> SQLValue { d.map { .text(DateFormatters.formatIsoDate($0)) } ?? .null }
    public static func optionalTimestamp(_ d: Date?) -> SQLValue { d.map { .text(DateFormatters.formatIsoTimestamp($0)) } ?? .null }
    public static func bool(_ b: Bool) -> SQLValue { .integer(b ? 1 : 0) }
}

public struct Row {
    let stmt: OpaquePointer?

    public init(stmt: OpaquePointer?) {
        self.stmt = stmt
    }

    private func index(of name: String) -> Int32 {
        guard let stmt = stmt else { return -1 }
        let n = sqlite3_column_count(stmt)
        for i in 0..<n {
            if let cName = sqlite3_column_name(stmt, i) {
                if String(cString: cName) == name { return i }
            }
        }
        return -1
    }

    private func index(_ i: Int32) -> Int32 { i }

    public func int(_ name: String) -> Int64 {
        let i = index(of: name)
        guard i >= 0, let stmt = stmt else { return 0 }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return 0 }
        return sqlite3_column_int64(stmt, i)
    }

    public func int(_ i: Int32) -> Int64 {
        guard let stmt = stmt else { return 0 }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return 0 }
        return sqlite3_column_int64(stmt, i)
    }

    public func text(_ name: String) -> String {
        let i = index(of: name)
        guard i >= 0, let stmt = stmt else { return "" }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return "" }
        guard let cStr = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: cStr)
    }

    public func text(_ i: Int32) -> String {
        guard let stmt = stmt else { return "" }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return "" }
        guard let cStr = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: cStr)
    }

    public func optionalText(_ name: String) -> String? {
        let i = index(of: name)
        guard i >= 0, let stmt = stmt else { return nil }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        guard let cStr = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: cStr)
    }

    public func date(_ name: String) -> Date {
        let s = text(name)
        return DateFormatters.parseDate(s) ?? Date(timeIntervalSince1970: 0)
    }

    public func date(_ i: Int32) -> Date {
        let s = text(i)
        return DateFormatters.parseDate(s) ?? Date(timeIntervalSince1970: 0)
    }

    public func timestamp(_ name: String) -> Date {
        let s = text(name)
        return DateFormatters.parseTimestamp(s) ?? Date(timeIntervalSince1970: 0)
    }

    public func timestamp(_ i: Int32) -> Date {
        let s = text(i)
        return DateFormatters.parseTimestamp(s) ?? Date(timeIntervalSince1970: 0)
    }

    public func optionalDate(_ name: String) -> Date? {
        let i = index(of: name)
        guard i >= 0, let stmt = stmt else { return nil }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        let s = String(cString: sqlite3_column_text(stmt, i))
        return DateFormatters.parseDate(s)
    }

    public func optionalDate(_ i: Int32) -> Date? {
        guard i >= 0, let stmt = stmt else { return nil }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        let s = String(cString: sqlite3_column_text(stmt, i))
        return DateFormatters.parseDate(s)
    }

    public func bool(_ name: String) -> Bool {
        int(name) != 0
    }

    public func bool(_ i: Int32) -> Bool {
        int(i) != 0
    }

    public func real(_ name: String) -> Double {
        let i = index(of: name)
        guard i >= 0, let stmt = stmt else { return 0 }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return 0 }
        return sqlite3_column_double(stmt, i)
    }

    public func real(_ i: Int32) -> Double {
        guard i >= 0, let stmt = stmt else { return 0 }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return 0 }
        return sqlite3_column_double(stmt, i)
    }

    public func optionalReal(_ name: String) -> Double? {
        let i = index(of: name)
        guard i >= 0, let stmt = stmt else { return nil }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, i)
    }

    public func data(_ name: String) -> Data {
        let i = index(of: name)
        guard i >= 0, let stmt = stmt else { return Data() }
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return Data() }
        guard let bytes = sqlite3_column_blob(stmt, i) else { return Data() }
        let count = Int(sqlite3_column_bytes(stmt, i))
        return Data(bytes: bytes, count: count)
    }
}

public final class SQLiteDatabase: @unchecked Sendable {

    public let path: String
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var inTransactionDepth: Int = 0
    private var statementCache: [String: OpaquePointer] = [:]

    public init(path: String, readonly: Bool = false) throws {
        self.path = path
        try sync {
            var h: OpaquePointer?
            var flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            if readonly {
                flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            }
            let rc = sqlite3_open_v2(path, &h, flags, nil)
            if rc != SQLITE_OK {
                let msg: String
                if let h = h {
                    msg = String(cString: sqlite3_errmsg(h))
                } else {
                    msg = "sqlite3_open_v2 returned \(rc)"
                }
                sqlite3_close(h)
                if rc == SQLITE_CANTOPEN || msg.localizedCaseInsensitiveContains("permission") {
                    throw AppError.database(.openFailed("Cannot open \(URL(fileURLWithPath: path).lastPathComponent): permission denied or unavailable. \(msg)"))
                }
                throw AppError.database(.openFailed(msg))
            }
            self.handle = h
            try applyPragmas()
        }
    }

    deinit {
        close()
    }

    private func finalizeStatementCacheNoLock() {
        for stmt in statementCache.values {
            sqlite3_finalize(stmt)
        }
        statementCache.removeAll()
    }

    private func sync<T>(_ block: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block()
    }

    private func applyPragmas() throws {
        try execNoLock("PRAGMA foreign_keys = ON")
        try execNoLock("PRAGMA journal_mode = WAL")
        try execNoLock("PRAGMA synchronous = NORMAL")
        try execNoLock("PRAGMA cache_size = -64000")
        try execNoLock("PRAGMA busy_timeout = 5000")
        try execNoLock("PRAGMA temp_store = MEMORY")
    }

    public func execute(_ sql: String) throws {
        try sync { try execNoLock(sql) }
    }

    public func execute(_ sql: String, _ bindings: [SQLValue]) throws {
        try sync { try execWithBindingsNoLock(sql, bindings) }
    }

    private func execNoLock(_ sql: String) throws {
        guard let handle = handle else {
            throw AppError.database(.openFailed("null handle"))
        }
        var errPtr: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errPtr)
        if rc != SQLITE_OK {
            let msg = errPtr.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errPtr)
            throw AppError.database(.execFailed(msg))
        }
    }

    private func execWithBindingsNoLock(_ sql: String, _ bindings: [SQLValue]) throws {
        let stmt = try preparedStatement(sql)
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        try bindAll(stmt, bindings)
        let step = sqlite3_step(stmt)
        if step != SQLITE_DONE && step != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw AppError.database(.stepFailed(msg))
        }
    }

    public func query<T>(_ sql: String,
                         bind: [SQLValue] = [],
                         row: (Row) throws -> T) throws -> [T] {
        try sync { try queryNoLock(sql, bind: bind, row: row) }
    }

    public func queryOne<T>(_ sql: String,
                            bind: [SQLValue] = [],
                            row: (Row) throws -> T) throws -> T? {
        try sync { try queryOneNoLock(sql, bind: bind, row: row) }
    }

    private func queryNoLock<T>(_ sql: String,
                                bind: [SQLValue],
                                row: (Row) throws -> T) throws -> [T] {
        let stmt = try preparedStatement(sql)
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        try bindAll(stmt, bind)
        var results: [T] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            if step != SQLITE_ROW {
                let msg = String(cString: sqlite3_errmsg(handle))
                throw AppError.database(.stepFailed(msg))
            }
            let r = Row(stmt: stmt)
            results.append(try row(r))
        }
        return results
    }

    private func queryOneNoLock<T>(_ sql: String,
                                   bind: [SQLValue],
                                   row: (Row) throws -> T) throws -> T? {
        let stmt = try preparedStatement(sql)
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        try bindAll(stmt, bind)
        let step = sqlite3_step(stmt)
        if step == SQLITE_DONE { return nil }
        if step != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw AppError.database(.stepFailed(msg))
        }
        let r = Row(stmt: stmt)
        return try row(r)
    }

    private func preparedStatement(_ sql: String) throws -> OpaquePointer {
        if let stmt = statementCache[sql] {
            let resetRc = sqlite3_reset(stmt)
            if resetRc == SQLITE_OK {
                sqlite3_clear_bindings(stmt)
                return stmt
            }
            sqlite3_finalize(stmt)
            statementCache.removeValue(forKey: sql)
        }
        var stmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard prep == SQLITE_OK, let stmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw AppError.database(.prepareFailed(msg))
        }
        statementCache[sql] = stmt
        return stmt
    }

    private func bindAll(_ stmt: OpaquePointer?, _ values: [SQLValue]) throws {
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch v {
            case .integer(let x):
                rc = sqlite3_bind_int64(stmt, idx, x)
            case .real(let x):
                rc = sqlite3_bind_double(stmt, idx, x)
            case .text(let s):
                rc = s.withCString { cStr in
                    sqlite3_bind_text(stmt, idx, cStr, -1, SQLITE_TRANSIENT_DESTRUCTOR)
                }
            case .blob(let data):
                rc = data.withUnsafeBytes { raw in
                    let baseAddress = raw.baseAddress
                    let count = Int32(data.count)
                    return sqlite3_bind_blob(stmt, idx, baseAddress, count, SQLITE_TRANSIENT_DESTRUCTOR)
                }
            case .null:
                rc = sqlite3_bind_null(stmt, idx)
            }
            if rc != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(stmt))
                throw AppError.database(.bindFailed("index \(idx): \(msg)"))
            }
        }
    }

    public func write(_ block: (SQLiteDatabase) throws -> Void) throws {
        try sync {
            if inTransactionDepth == 0 {
                try execNoLock("BEGIN IMMEDIATE")
            }
            inTransactionDepth += 1
            do {
                try block(self)
                inTransactionDepth -= 1
                if inTransactionDepth == 0 {
                    try execNoLock("COMMIT")
                }
            } catch {
                inTransactionDepth -= 1
                if inTransactionDepth == 0 {
                    _ = try? execNoLock("ROLLBACK")
                }
                throw error
            }
        }
    }

    public func lastInsertRowID() -> Int64 {
        sync {
            guard let handle = handle else { return 0 }
            return sqlite3_last_insert_rowid(handle)
        }
    }

    public func changes() -> Int32 {
        sync {
            guard let handle = handle else { return 0 }
            return sqlite3_changes(handle)
        }
    }

    public func userVersion() -> Int {
        do {
            let v: Int64? = try sync {
                try queryOneNoLock("PRAGMA user_version", bind: [], row: { r in r.int(0) })
            }
            return Int(v ?? 0)
        } catch {
            return 0
        }
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    public func checkpoint() throws {
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    public func vacuum() throws {
        try sync { try execNoLock("VACUUM") }
    }

    public func close() {
        sync {
            if let h = handle {
                _ = try? execNoLock("PRAGMA wal_checkpoint(TRUNCATE)")
                finalizeStatementCacheNoLock()
                sqlite3_db_release_memory(h)
                sqlite3_close(h)
                sqlite3_release_memory(Int32.max)
                handle = nil
            }
        }
    }
}
