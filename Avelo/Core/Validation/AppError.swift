import Foundation

public enum AppError: Error, Sendable, Equatable, Identifiable {
    case validation(ValidationError)
    case database(SQLiteError)
    case featureUnavailable(String)
    case fileSystem(String)
    case unexpected(String)
    case businessRule(String)
    case duplicateSalary(String)
    case groupHasChildren(String)
    case negativeStock(String)
    case notFound(String)

    public var localizedMessage: String {
        switch self {
        case .validation(let e):
            return e.message
        case .database(let e):
            return "Database error: \(e.message)"
        case .featureUnavailable(let s):
            return "Feature unavailable: \(s)"
        case .fileSystem(let s):
            return "File system error: \(s)"
        case .unexpected(let s):
            return "Unexpected error: \(s)"
        case .businessRule(let s):
            return s
        case .duplicateSalary(let s):
            return s
        case .groupHasChildren(let s):
            return s
        case .negativeStock(let s):
            return s
        case .notFound(let s):
            return "Not found: \(s)"
        }
    }

    public static func wrap(_ error: Error) -> AppError {
        if let appErr = error as? AppError {
            return appErr
        }
        if let sqliteErr = error as? SQLiteError {
            return .database(sqliteErr)
        }
        return .unexpected(error.localizedDescription)
    }

    public var id: String {
        switch self {
        case .validation(let e):  return "validation-\(e.code.rawValue)"
        case .database(let e):    return "database-\(e.message.hashValue)"
        case .featureUnavailable(let s): return "unavail-\(s.hashValue)"
        case .fileSystem(let s):   return "fs-\(s.hashValue)"
        case .unexpected(let s):   return "unexpected-\(s.hashValue)"
        case .businessRule(let s): return "biz-\(s.hashValue)"
        case .duplicateSalary(let s): return "salary-dup-\(s.hashValue)"
        case .groupHasChildren(let s): return "group-children-\(s.hashValue)"
        case .negativeStock(let s): return "negative-\(s.hashValue)"
        case .notFound(let s):     return "404-\(s.hashValue)"
        }
    }
}

public enum SQLiteError: Error, Sendable, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case execFailed(String)
    case transactionFailed(String)
    case rowReadFailed(String)
    case schemaMismatch(String)
    case migrationFailed(String)
    case checksumMismatch
    case missingEncryptionKey(String)
    case wrongEncryptionKey(String)

    public var message: String {
        switch self {
        case .openFailed(let s):        return "open: \(s)"
        case .prepareFailed(let s):     return "prepare: \(s)"
        case .stepFailed(let s):        return "step: \(s)"
        case .bindFailed(let s):        return "bind: \(s)"
        case .execFailed(let s):        return "exec: \(s)"
        case .transactionFailed(let s): return "transaction: \(s)"
        case .rowReadFailed(let s):     return "row: \(s)"
        case .schemaMismatch(let s):    return s
        case .migrationFailed(let s):   return s
        case .checksumMismatch:         return "backup checksum does not match"
        case .missingEncryptionKey(let s): return s
        case .wrongEncryptionKey(let s): return s
        }
    }
}

public struct InventoryPromptContext: Hashable, Sendable {
    public struct Line: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let itemId: InventoryItem.ID
        public let itemName: String
        public let unit: String
        public let quantity: Int64
        public let unitCostPaise: Int64
        public let direction: MovementType

        public init(id: UUID = UUID(),
                    itemId: InventoryItem.ID,
                    itemName: String,
                    unit: String,
                    quantity: Int64,
                    unitCostPaise: Int64,
                    direction: MovementType) {
            self.id = id
            self.itemId = itemId
            self.itemName = itemName
            self.unit = unit
            self.quantity = quantity
            self.unitCostPaise = unitCostPaise
            self.direction = direction
        }
    }

    public let voucherId: Voucher.ID
    public let voucherNumber: String
    public let lines: [Line]

    public init(voucherId: Voucher.ID, voucherNumber: String, lines: [Line]) {
        self.voucherId = voucherId
        self.voucherNumber = voucherNumber
        self.lines = lines
    }
}
