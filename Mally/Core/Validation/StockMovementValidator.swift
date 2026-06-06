import Foundation

public struct StockMovementValidator: Sendable {

    public struct Input: Sendable {
        public var itemId: InventoryItem.ID
        public var date: Date
        public var movementType: MovementType
        public var quantity: Int64
        public var unitCostPaise: Int64
        public var totalValuePaise: Int64
        public var currentOnHandQty: Int64

        public init(itemId: InventoryItem.ID,
                    date: Date,
                    movementType: MovementType,
                    quantity: Int64,
                    unitCostPaise: Int64,
                    totalValuePaise: Int64,
                    currentOnHandQty: Int64) {
            self.itemId = itemId
            self.date = date
            self.movementType = movementType
            self.quantity = quantity
            self.unitCostPaise = unitCostPaise
            self.totalValuePaise = totalValuePaise
            self.currentOnHandQty = currentOnHandQty
        }
    }

    public init() {}

    public func validate(_ input: Input) -> ValidationResult {
        var errors: [ValidationError] = []

        if input.quantity <= 0 {
            errors.append(ValidationError(
                code: .stockMovementQuantityZero,
                field: "quantity",
                message: "Quantity must be greater than zero."
            ))
        }

        if input.unitCostPaise < 0 {
            errors.append(ValidationError(
                code: .stockMovementCostMismatch,
                field: "unitCost",
                message: "Unit cost cannot be negative."
            ))
        }

        let expectedTotal = input.quantity * input.unitCostPaise
        if expectedTotal != input.totalValuePaise {
            errors.append(ValidationError(
                code: .stockMovementCostMismatch,
                field: "totalValue",
                message: "Total value (\(Currency.formatPaise(input.totalValuePaise, style: .plain))) does not equal quantity × unit cost."
            ))
        }

        if input.movementType == .stockOut && input.quantity > input.currentOnHandQty {
            errors.append(ValidationError(
                code: .quantityExceedsStock,
                field: "quantity",
                message: "Out quantity (\(input.quantity)) exceeds current stock (\(input.currentOnHandQty))."
            ))
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }
}
