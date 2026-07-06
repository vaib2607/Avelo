import Foundation

public struct StockMovementValidator: Sendable {

    public struct Input: Sendable {
        public var itemId: InventoryItem.ID
        public var date: Date
        public var movementType: MovementType
        public var quantity: ExactQuantity
        public var unitCostPaise: Int64
        public var totalValuePaise: Int64
        public var currentOnHandQty: ExactQuantity
        public var allowAuthoritativeTotalOverride: Bool

        public init(itemId: InventoryItem.ID,
                    date: Date,
                    movementType: MovementType,
                    quantity: ExactQuantity,
                    unitCostPaise: Int64,
                    totalValuePaise: Int64,
                    currentOnHandQty: ExactQuantity,
                    allowAuthoritativeTotalOverride: Bool = false) {
            self.itemId = itemId
            self.date = date
            self.movementType = movementType
            self.quantity = quantity
            self.unitCostPaise = unitCostPaise
            self.totalValuePaise = totalValuePaise
            self.currentOnHandQty = currentOnHandQty
            self.allowAuthoritativeTotalOverride = allowAuthoritativeTotalOverride
        }

        public init(itemId: InventoryItem.ID,
                    date: Date,
                    movementType: MovementType,
                    quantity: Int64,
                    unitCostPaise: Int64,
                    totalValuePaise: Int64,
                    currentOnHandQty: Int64,
                    allowAuthoritativeTotalOverride: Bool = false) {
            self.init(
                itemId: itemId,
                date: date,
                movementType: movementType,
                quantity: try! ExactQuantity.whole(quantity),
                unitCostPaise: unitCostPaise,
                totalValuePaise: totalValuePaise,
                currentOnHandQty: try! ExactQuantity.whole(currentOnHandQty),
                allowAuthoritativeTotalOverride: allowAuthoritativeTotalOverride
            )
        }
    }

    public init() {}

    public func validate(_ input: Input) -> ValidationResult {
        var errors: [ValidationError] = []

        if input.quantity.isZero {
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

        let expectedTotal: Int64?
        do {
            expectedTotal = try input.quantity.multiplied(byUnitCostPaise: input.unitCostPaise, context: "validating stock movement total value")
        } catch {
            expectedTotal = nil
            errors.append(ValidationError(
                code: .arithmeticOverflow,
                field: "totalValue",
                message: "Quantity and unit cost cannot be represented exactly in paise."
            ))
        }

        if input.movementType != .stockOut,
           !input.allowAuthoritativeTotalOverride,
           let expectedTotal,
           expectedTotal != input.totalValuePaise {
            errors.append(ValidationError(
                code: .stockMovementCostMismatch,
                field: "totalValue",
                message: "Total value (\(Currency.formatPaise(input.totalValuePaise, style: .plain))) does not equal quantity x unit cost."
            ))
        }

        if input.movementType == .stockOut && (try? ExactQuantity.compare(input.quantity, input.currentOnHandQty)) == .orderedDescending {
            errors.append(ValidationError(
                code: .quantityExceedsStock,
                field: "quantity",
                message: "Out quantity (\(input.quantity.displayString)) exceeds current stock (\(input.currentOnHandQty.displayString))."
            ))
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }
}
