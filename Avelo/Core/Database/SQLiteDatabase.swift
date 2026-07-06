import Foundation
import CSQLCipher
import os

let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
let AveloDBLogger = Logger(subsystem: "com.avelo.desktop", category: "database")

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

final class PreparedStatementBox: @unchecked Sendable {
    let stmt: OpaquePointer
    var columnIndexCache: [String: Int32] = [:]
    var lastUsedAt: Int = 0
    let isTransient: Bool

    init(stmt: OpaquePointer, isTransient: Bool = false) {
        self.stmt = stmt
        self.isTransient = isTransient
    }
}

public struct Row {
    fileprivate let box: PreparedStatementBox?

    fileprivate init(box: PreparedStatementBox?) {
        self.box = box
    }

    private func index(of name: String) -> Int32 {
        guard let box else { return -1 }
        if let cached = box.columnIndexCache[name] { return cached }
        let n = sqlite3_column_count(box.stmt)
        for i in 0..<n {
            if let cName = sqlite3_column_name(box.stmt, i), String(cString: cName) == name {
                box.columnIndexCache[name] = i
                return i
            }
        }
        box.columnIndexCache[name] = -1
        return -1
    }

    private func index(_ i: Int32) -> Int32 { i }

    private func requireColumnIndex(_ name: String) throws -> Int32 {
        let i = index(of: name)
        guard i >= 0, box != nil else {
            throw AppError.database(.rowReadFailed("missing required column \(name)"))
        }
        return i
    }

    public func requiredText(_ name: String) throws -> String {
        let i = try requireColumnIndex(name)
        guard let box else {
            throw AppError.database(.rowReadFailed("missing row data for column \(name)"))
        }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL {
            throw AppError.database(.rowReadFailed("null value for required column \(name)"))
        }
        guard let cStr = sqlite3_column_text(box.stmt, i) else {
            throw AppError.database(.rowReadFailed("invalid text value for column \(name)"))
        }
        return String(cString: cStr)
    }

    public func checkedOptionalText(_ name: String) throws -> String? {
        let i = try requireColumnIndex(name)
        guard let box else {
            throw AppError.database(.rowReadFailed("missing row data for column \(name)"))
        }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return nil }
        guard let cStr = sqlite3_column_text(box.stmt, i) else {
            throw AppError.database(.rowReadFailed("invalid text value for column \(name)"))
        }
        return String(cString: cStr)
    }

    public func requiredInt(_ name: String) throws -> Int64 {
        let i = try requireColumnIndex(name)
        guard let box else {
            throw AppError.database(.rowReadFailed("missing row data for column \(name)"))
        }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL {
            throw AppError.database(.rowReadFailed("null value for required column \(name)"))
        }
        return sqlite3_column_int64(box.stmt, i)
    }

    public func checkedOptionalInt(_ name: String) throws -> Int64? {
        let i = try requireColumnIndex(name)
        guard let box else {
            throw AppError.database(.rowReadFailed("missing row data for column \(name)"))
        }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(box.stmt, i)
    }

    public func requiredBool(_ name: String) throws -> Bool {
        let raw = try requiredInt(name)
        switch raw {
        case 0: return false
        case 1: return true
        default:
            throw AppError.database(.rowReadFailed("invalid boolean value for column \(name): \(raw)"))
        }
    }

    public func requiredDate(_ name: String) throws -> Date {
        let s = try requiredText(name)
        guard let date = DateFormatters.parseDate(s) else {
            throw AppError.database(.rowReadFailed("invalid date value for column \(name)"))
        }
        return date
    }

    public func checkedOptionalDate(_ name: String) throws -> Date? {
        guard let s = try checkedOptionalText(name) else { return nil }
        guard let date = DateFormatters.parseDate(s) else {
            throw AppError.database(.rowReadFailed("invalid date value for column \(name)"))
        }
        return date
    }

    public func enumValue<T: RawRepresentable>(_ name: String, as type: T.Type = T.self) throws -> T where T.RawValue == String {
        let raw = try requiredText(name)
        guard let value = T(rawValue: raw) else {
            throw AppError.database(.rowReadFailed("invalid \(String(describing: T.self)) value for column \(name): \(raw)"))
        }
        return value
    }

    public func int(_ name: String) -> Int64 {
        let i = index(of: name)
        guard i >= 0, let box else { return 0 }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return 0 }
        return sqlite3_column_int64(box.stmt, i)
    }

    public func int(_ i: Int32) -> Int64 {
        guard let box else { return 0 }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return 0 }
        return sqlite3_column_int64(box.stmt, i)
    }

    public func text(_ name: String) -> String {
        let i = index(of: name)
        guard i >= 0, let box else { return "" }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return "" }
        guard let cStr = sqlite3_column_text(box.stmt, i) else { return "" }
        return String(cString: cStr)
    }

    public func text(_ i: Int32) -> String {
        guard let box else { return "" }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return "" }
        guard let cStr = sqlite3_column_text(box.stmt, i) else { return "" }
        return String(cString: cStr)
    }

    public func optionalText(_ name: String) -> String? {
        let i = index(of: name)
        guard i >= 0, let box else { return nil }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return nil }
        guard let cStr = sqlite3_column_text(box.stmt, i) else { return nil }
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

    public func timestamp(_ name: String) throws -> Date {
        let s = try requiredText(name)
        guard let date = DateFormatters.parseTimestamp(s) else {
            throw AppError.database(.rowReadFailed("invalid timestamp value for column \(name)"))
        }
        return date
    }

    public func timestamp(_ i: Int32) throws -> Date {
        let s = text(i)
        guard let date = DateFormatters.parseTimestamp(s) else {
            throw AppError.database(.rowReadFailed("invalid timestamp value at column \(i)"))
        }
        return date
    }

    public func optionalDate(_ name: String) -> Date? {
        let i = index(of: name)
        guard i >= 0, let box else { return nil }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return nil }
        guard let cStr = sqlite3_column_text(box.stmt, i) else { return nil }
        let s = String(cString: cStr)
        return DateFormatters.parseDate(s)
    }

    public func optionalDate(_ i: Int32) -> Date? {
        guard i >= 0, let box else { return nil }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return nil }
        guard let cStr = sqlite3_column_text(box.stmt, i) else { return nil }
        let s = String(cString: cStr)
        return DateFormatters.parseDate(s)
    }

    public func optionalTimestamp(_ name: String) throws -> Date? {
        guard let s = try checkedOptionalText(name) else { return nil }
        guard let date = DateFormatters.parseTimestamp(s) else {
            throw AppError.database(.rowReadFailed("invalid timestamp value for column \(name)"))
        }
        return date
    }

    public func bool(_ name: String) -> Bool {
        int(name) != 0
    }

    public func bool(_ i: Int32) -> Bool {
        int(i) != 0
    }

    public func real(_ name: String) -> Double {
        let i = index(of: name)
        guard i >= 0, let box else { return 0 }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return 0 }
        return sqlite3_column_double(box.stmt, i)
    }

    public func real(_ i: Int32) -> Double {
        guard i >= 0, let box else { return 0 }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return 0 }
        return sqlite3_column_double(box.stmt, i)
    }

    public func optionalReal(_ name: String) -> Double? {
        let i = index(of: name)
        guard i >= 0, let box else { return nil }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return nil }
        return sqlite3_column_double(box.stmt, i)
    }

    public func optionalInt(_ name: String) -> Int64? {
        let i = index(of: name)
        guard i >= 0, let box else { return nil }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(box.stmt, i)
    }

    public func data(_ name: String) -> Data {
        let i = index(of: name)
        guard i >= 0, let box else { return Data() }
        if sqlite3_column_type(box.stmt, i) == SQLITE_NULL { return Data() }
        guard let bytes = sqlite3_column_blob(box.stmt, i) else { return Data() }
        let count = Int(sqlite3_column_bytes(box.stmt, i))
        return Data(bytes: bytes, count: count)
    }
}

public final class SQLiteDatabase: @unchecked Sendable {

    public enum EncryptionKey: Sendable, Equatable {
        case unencrypted
        case passphrase(String)
        case raw(Data)
    }

    public let path: String
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var inTransactionDepth: Int = 0
    private var inReadTransactionDepth: Int = 0
    private var statementCache: [String: PreparedStatementBox] = [:]
    private var statementUseCounter: Int = 0
    private let maxCachedStatements = 256

    public convenience init(path: String, readonly: Bool = false, key: Data? = nil) throws {
        try self.init(path: path, readonly: readonly, encryptionKey: key.map { .raw($0) } ?? .unencrypted)
    }

    public init(path: String, readonly: Bool = false, encryptionKey: EncryptionKey) throws {
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
            try applyEncryptionKey(encryptionKey)
            try applyPragmas()
        }
    }

    deinit {
        close()
    }

    private func finalizeStatementCacheNoLock() {
        for box in statementCache.values {
            sqlite3_finalize(box.stmt)
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

    private func applyEncryptionKey(_ key: EncryptionKey) throws {
        guard path != ":memory:" else { return }
        switch key {
        case .unencrypted:
            return
        case .passphrase(let value):
            guard !value.isEmpty else {
                throw AppError.database(.missingEncryptionKey("Encryption passphrase is empty."))
            }
            try execNoLock("PRAGMA key = \(Self.sqlLiteral(value))")
        case .raw(let data):
            guard data.count == 32 else {
                throw AppError.database(.missingEncryptionKey("Company encryption key must be 32 bytes."))
            }
            try execNoLock("PRAGMA key = \"x'\(Self.hex(data))'\"")
        }
        do {
            _ = try queryOneNoLock("SELECT count(*) FROM sqlite_master", bind: []) { $0.int(0) }
        } catch {
            throw AppError.database(.wrongEncryptionKey("Database encryption key rejected or file is not a valid encrypted store."))
        }
    }

    static let legacyHardcodedPassphrase = ["Avelo", "v2", "local", "sqlcipher", "commoncrypto", "store"].joined(separator: ".")

    private static func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public func execute(_ sql: String) throws {
        try sync { try execNoLock(sql) }
    }

    public func execute(_ sql: String, _ bindings: [SQLValue]) throws {
        try sync { try execWithBindingsNoLock(sql, bindings) }
    }

    public func read<T>(_ block: (SQLiteDatabase) throws -> T) throws -> T {
        try sync {
            if inReadTransactionDepth == 0 {
                try execNoLock("BEGIN DEFERRED")
            }
            inReadTransactionDepth += 1
            do {
                let result = try block(self)
                inReadTransactionDepth -= 1
                if inReadTransactionDepth == 0 {
                    try execNoLock("COMMIT")
                }
                return result
            } catch {
                inReadTransactionDepth -= 1
                if inReadTransactionDepth == 0 {
                    do {
                        try execNoLock("ROLLBACK")
                    } catch {
                        AveloDBLogger.error("rollback failed after read transaction error")
                    }
                    inReadTransactionDepth = 0
                }
                throw error
            }
        }
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
            AveloDBLogger.error("exec failed: \(msg, privacy: .public)")
            throw AppError.database(.execFailed(msg))
        }
    }

    private func execWithBindingsNoLock(_ sql: String, _ bindings: [SQLValue]) throws {
        let box = try preparedStatement(sql)
        let stmt = box.stmt
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            if box.isTransient {
                sqlite3_finalize(stmt)
            }
        }
        try bindAll(stmt, bindings)
        let step = sqlite3_step(stmt)
        if step != SQLITE_DONE && step != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(handle))
            AveloDBLogger.error("step failed: \(msg, privacy: .public)")
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
        let box = try preparedStatement(sql)
        let stmt = box.stmt
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            if box.isTransient {
                sqlite3_finalize(stmt)
            }
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
            let r = Row(box: box)
            results.append(try row(r))
        }
        return results
    }

    private func queryOneNoLock<T>(_ sql: String,
                                   bind: [SQLValue],
                                   row: (Row) throws -> T) throws -> T? {
        let box = try preparedStatement(sql)
        let stmt = box.stmt
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            if box.isTransient {
                sqlite3_finalize(stmt)
            }
        }
        try bindAll(stmt, bind)
        let step = sqlite3_step(stmt)
        if step == SQLITE_DONE { return nil }
        if step != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw AppError.database(.stepFailed(msg))
        }
        let r = Row(box: box)
        return try row(r)
    }

    private func preparedStatement(_ sql: String) throws -> PreparedStatementBox {
        if let box = statementCache[sql] {
            if sqlite3_stmt_busy(box.stmt) == 0 {
                sqlite3_clear_bindings(box.stmt)
                touchCachedStatement(sql, box: box)
                return box
            }
            // The cached statement is still active in a recursive read path.
            // Prepare a one-off statement so the outer cursor is not disturbed.
            return try prepareTransientStatement(sql)
        }
        return try prepareAndCacheStatement(sql)
    }

    private func prepareAndCacheStatement(_ sql: String) throws -> PreparedStatementBox {
        let box = try prepareStatementBox(sql)
        touchCachedStatement(sql, box: box)
        statementCache[sql] = box
        evictIfNeededNoLock()
        return box
    }

    private func prepareTransientStatement(_ sql: String) throws -> PreparedStatementBox {
        try prepareStatementBox(sql, transient: true)
    }

    private func prepareStatementBox(_ sql: String, transient: Bool = false) throws -> PreparedStatementBox {
        var stmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard prep == SQLITE_OK, let stmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(handle))
            AveloDBLogger.error("prepare failed: \(msg, privacy: .public)")
            throw AppError.database(.prepareFailed(msg))
        }
        return PreparedStatementBox(stmt: stmt, isTransient: transient)
    }

    private func touchCachedStatement(_ sql: String, box: PreparedStatementBox) {
        statementUseCounter &+= 1
        box.lastUsedAt = statementUseCounter
    }

    private func evictIfNeededNoLock() {
        guard statementCache.count > maxCachedStatements else { return }
        if let victim = statementCache.min(by: { $0.value.lastUsedAt < $1.value.lastUsedAt }) {
            sqlite3_finalize(victim.value.stmt)
            statementCache.removeValue(forKey: victim.key)
        }
    }

    internal var debugStatementCacheCount: Int {
        sync { statementCache.count }
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
                let msg = String(cString: sqlite3_errmsg(handle))
                AveloDBLogger.error("bind failed: \(msg, privacy: .public)")
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
                    do {
                        try execNoLock("ROLLBACK")
                    } catch {
                        AveloDBLogger.error("rollback failed after transaction error")
                    }
                    inTransactionDepth = 0
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
                do {
                    try execNoLock("PRAGMA wal_checkpoint(TRUNCATE)")
                } catch {
                    AveloDBLogger.error("checkpoint on close failed")
                }
                finalizeStatementCacheNoLock()
                sqlite3_db_release_memory(h)
                sqlite3_close(h)
                sqlite3_release_memory(Int32.max)
                handle = nil
            }
        }
    }
}
