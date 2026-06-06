import Foundation

public struct StockMovementValidator: Sendable {

    public struct Input: Sendable {
        public var itemId: InventoryItem.ID
        public var date: Date
        public var movementType: MovementType
        public var quantity: Double
        public var unitCostPaise: Int64
        public var totalValuePaise: Int64
        public var currentOnHandQty: Double

        public init(itemId: InventoryItem.ID,
                    date: Date,
                    movementType: MovementType,
                    quantity: Double,
                    unitCostPaise: Int64,
                    totalValuePaise: Int64,
                    currentOnHandQty: Double) {
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

        // totalValuePaise = round(quantity × unitCostPaise); allow ±1 paise for rounding.
        let expectedTotal = Int64((input.quantity * Double(input.unitCostPaise)).rounded())
        if abs(expectedTotal - input.totalValuePaise) > 1 {
            errors.append(ValidationError(
                code: .stockMovementCostMismatch,
                field: "totalValue",
                message: "Total value (\(Currency.formatPaise(input.totalValuePaise, style: .plain))) does not equal quantity × unit cost."
            ))
        }

        let outTypes: Set<MovementType> = [.stockOut, .sale, .purchaseReturn, .adjustmentOut]
        if outTypes.contains(input.movementType) && input.quantity > input.currentOnHandQty {
            errors.append(ValidationError(
                code: .quantityExceedsStock,
                field: "quantity",
                message: String(format: "Out quantity (%.3f) exceeds current stock (%.3f).",
                                input.quantity, input.currentOnHandQty)
            ))
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }
}
