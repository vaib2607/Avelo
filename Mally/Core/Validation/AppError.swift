import Foundation

public enum AppError: Error, Sendable, Equatable {
    case validation(ValidationError)
    case database(SQLiteError)
    case featureUnavailable(String)
    case fileSystem(String)
    case unexpected(String)
    case businessRule(String)
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
        case .notFound(let s):
            return "Not found: \(s)"
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
