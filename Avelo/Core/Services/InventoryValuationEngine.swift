import Foundation

struct InventoryValuationEngine: Sendable {
    struct Layer: Hashable, Sendable {
        let movementId: StockMovement.ID
        let receiptDate: Date
        let createdAt: Date
        var remainingQuantity: ExactQuantity
        var remainingValuePaise: Int64
    }

    struct ValuedMovement: Hashable, Sendable {
        let movement: StockMovement
        let authoritativeTotalValuePaise: Int64
    }

    struct Snapshot: Sendable {
        let valuedMovements: [ValuedMovement]
        let remainingLayers: [Layer]
        let onHandQuantity: SignedExactQuantity
        let onHandValuePaise: Int64
        let inboundQuantity: ExactQuantity
        let outboundQuantity: ExactQuantity
        let adjustmentQuantity: ExactQuantity
        let inboundValuePaise: Int64
        let outboundValuePaise: Int64
    }

    func replay(movements: [StockMovement], valuationMethod: ValuationMethod) throws -> Snapshot {
        let ordered = movements.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var valued: [ValuedMovement] = []
        var layers: [Layer] = []
        var onHand = SignedExactQuantity.zero
        var onHandValue: Int64 = 0
        var inQty = try ExactQuantity.whole(0)
        var outQty = try ExactQuantity.whole(0)
        var adjQty = try ExactQuantity.whole(0)
        var inValue: Int64 = 0
        var outValue: Int64 = 0

        for movement in ordered {
            switch movement.movementType {
            case .stockIn, .adjustment:
                let totalValue = movement.totalValuePaise
                valued.append(.init(movement: movement, authoritativeTotalValuePaise: totalValue))
                layers.append(.init(
                    movementId: movement.id,
                    receiptDate: movement.date,
                    createdAt: movement.createdAt,
                    remainingQuantity: movement.quantity,
                    remainingValuePaise: totalValue
                ))
                onHand = try ExactQuantity.signedAdd(onHand, try SignedExactQuantity(sign: .positive, magnitude: movement.quantity), context: "summing valued on-hand quantity")
                onHandValue = try CheckedMath.add(onHandValue, totalValue, context: "summing valued on-hand value")
                if movement.movementType == .stockIn {
                    inQty = try ExactQuantity.add(inQty, movement.quantity, context: "summing valued inbound quantity")
                    inValue = try CheckedMath.add(inValue, totalValue, context: "summing valued inbound value")
                } else {
                    adjQty = try ExactQuantity.add(adjQty, movement.quantity, context: "summing valued adjustment quantity")
                }
            case .stockOut:
                let consumedValue = try consume(movement: movement, valuationMethod: valuationMethod, layers: &layers)
                valued.append(.init(movement: movement, authoritativeTotalValuePaise: consumedValue))
                onHand = try ExactQuantity.signedAdd(onHand, try SignedExactQuantity(sign: .negative, magnitude: movement.quantity), context: "summing valued on-hand quantity")
                onHandValue = try CheckedMath.subtract(onHandValue, consumedValue, context: "summing valued on-hand value")
                outQty = try ExactQuantity.add(outQty, movement.quantity, context: "summing valued outbound quantity")
                outValue = try CheckedMath.add(outValue, consumedValue, context: "summing valued outbound value")
            }
        }

        return Snapshot(
            valuedMovements: valued,
            remainingLayers: layers,
            onHandQuantity: onHand,
            onHandValuePaise: onHandValue,
            inboundQuantity: inQty,
            outboundQuantity: outQty,
            adjustmentQuantity: adjQty,
            inboundValuePaise: inValue,
            outboundValuePaise: outValue
        )
    }

    private func consume(movement: StockMovement, valuationMethod: ValuationMethod, layers: inout [Layer]) throws -> Int64 {
        if let reversedMovementId = movement.reversedMovementId {
            return try consumeTargetedLayer(
                targetMovementId: reversedMovementId,
                quantity: movement.quantity,
                layers: &layers
            )
        }
        switch valuationMethod {
        case .fifo:
            return try consumeFIFO(quantity: movement.quantity, layers: &layers)
        case .weightedAverage:
            return try consumeWeightedAverage(quantity: movement.quantity, layers: &layers)
        }
    }

    private func consumeTargetedLayer(targetMovementId: StockMovement.ID,
                                      quantity: ExactQuantity,
                                      layers: inout [Layer]) throws -> Int64 {
        guard let index = layers.firstIndex(where: { $0.movementId == targetMovementId }) else {
            throw AppError.businessRule("Reversal target layer is unavailable.")
        }
        let available = layers[index].remainingQuantity
        guard try ExactQuantity.compare(available, quantity) != .orderedAscending else {
            throw AppError.validation(.init(code: .quantityExceedsStock, field: "quantity", message: "Reversal exceeds the remaining target layer quantity."))
        }
        let takingWholeLayer = try ExactQuantity.compare(available, quantity) == .orderedSame
        if takingWholeLayer {
            let consumedValue = layers[index].remainingValuePaise
            layers[index].remainingQuantity = try ExactQuantity.whole(0)
            layers[index].remainingValuePaise = 0
            return consumedValue
        }
        let consumedValue = try proratedValue(
            valuePaise: layers[index].remainingValuePaise,
            consumedQuantity: quantity,
            availableQuantity: available,
            context: "allocating targeted reversal layer value"
        )
        layers[index].remainingQuantity = try ExactQuantity.subtract(available, quantity, context: "reducing targeted reversal layer quantity")
        layers[index].remainingValuePaise = try CheckedMath.subtract(layers[index].remainingValuePaise, consumedValue, context: "reducing targeted reversal layer value")
        return consumedValue
    }

    private func consumeFIFO(quantity: ExactQuantity, layers: inout [Layer]) throws -> Int64 {
        var remaining = quantity
        var consumedValue: Int64 = 0

        for index in layers.indices {
            if remaining.isZero { break }
            if layers[index].remainingQuantity.isZero { continue }
            let available = layers[index].remainingQuantity
            let comparison = try ExactQuantity.compare(available, remaining)
            let take = comparison == .orderedAscending ? available : remaining
            let takingWholeLayer = try ExactQuantity.compare(take, available) == .orderedSame
            let layerValue: Int64
            if takingWholeLayer {
                layerValue = layers[index].remainingValuePaise
                layers[index].remainingQuantity = try ExactQuantity.whole(0)
                layers[index].remainingValuePaise = 0
            } else {
                layerValue = try proratedValue(
                    valuePaise: layers[index].remainingValuePaise,
                    consumedQuantity: take,
                    availableQuantity: available,
                    context: "allocating FIFO layer value"
                )
                layers[index].remainingQuantity = try ExactQuantity.subtract(available, take, context: "reducing FIFO layer quantity")
                layers[index].remainingValuePaise = try CheckedMath.subtract(layers[index].remainingValuePaise, layerValue, context: "reducing FIFO layer value")
            }
            consumedValue = try CheckedMath.add(consumedValue, layerValue, context: "summing FIFO consumed value")
            remaining = try ExactQuantity.subtract(remaining, take, context: "reducing FIFO remaining quantity")
        }

        guard remaining.isZero else {
            throw AppError.validation(.init(code: .quantityExceedsStock, field: "quantity", message: "Out quantity exceeds current stock."))
        }
        return consumedValue
    }

    private func consumeWeightedAverage(quantity: ExactQuantity, layers: inout [Layer]) throws -> Int64 {
        let aggregateQuantity = try layers.reduce(into: ExactQuantity.whole(0)) { partial, layer in
            partial = try ExactQuantity.add(partial, layer.remainingQuantity, context: "summing weighted-average layer quantity")
        }
        let aggregateValue = try CheckedMath.sum(layers.map(\.remainingValuePaise), context: "summing weighted-average layer value")
        guard try ExactQuantity.compare(aggregateQuantity, quantity) != .orderedAscending else {
            throw AppError.validation(.init(code: .quantityExceedsStock, field: "quantity", message: "Out quantity exceeds current stock."))
        }

        let consumingAll = try ExactQuantity.compare(aggregateQuantity, quantity) == .orderedSame
        let consumedValue = consumingAll ? aggregateValue : try proratedValue(
            valuePaise: aggregateValue,
            consumedQuantity: quantity,
            availableQuantity: aggregateQuantity,
            context: "allocating weighted-average value"
        )

        if consumingAll {
            for index in layers.indices {
                layers[index].remainingQuantity = try ExactQuantity.whole(0)
                layers[index].remainingValuePaise = 0
            }
            return consumedValue
        }

        var remainingToReduce = quantity
        var remainingValueToReduce = consumedValue
        for index in layers.indices {
            if remainingToReduce.isZero { break }
            let available = layers[index].remainingQuantity
            if available.isZero { continue }
            let comparison = try ExactQuantity.compare(available, remainingToReduce)
            let take = comparison == .orderedAscending ? available : remainingToReduce
            let takingWholeLayer = try ExactQuantity.compare(take, available) == .orderedSame
            let layerValueReduction: Int64
            if takingWholeLayer {
                layerValueReduction = min(layers[index].remainingValuePaise, remainingValueToReduce)
                layers[index].remainingQuantity = try ExactQuantity.whole(0)
                layers[index].remainingValuePaise = try CheckedMath.subtract(layers[index].remainingValuePaise, layerValueReduction, context: "clearing weighted-average layer value")
            } else {
                layerValueReduction = try proratedValue(
                    valuePaise: layers[index].remainingValuePaise,
                    consumedQuantity: take,
                    availableQuantity: available,
                    context: "allocating weighted-average layer reduction"
                )
                layers[index].remainingQuantity = try ExactQuantity.subtract(available, take, context: "reducing weighted-average layer quantity")
                layers[index].remainingValuePaise = try CheckedMath.subtract(layers[index].remainingValuePaise, layerValueReduction, context: "reducing weighted-average layer value")
            }
            remainingToReduce = try ExactQuantity.subtract(remainingToReduce, take, context: "reducing weighted-average remaining quantity")
            remainingValueToReduce = try CheckedMath.subtract(remainingValueToReduce, layerValueReduction, context: "reducing weighted-average remaining value")
        }

        if remainingValueToReduce > 0 {
            guard let lastNonZero = layers.indices.reversed().first(where: { layers[$0].remainingValuePaise > 0 }) else {
                throw AppError.businessRule("Weighted-average residual paise allocation failed.")
            }
            layers[lastNonZero].remainingValuePaise = try CheckedMath.subtract(layers[lastNonZero].remainingValuePaise, remainingValueToReduce, context: "allocating weighted-average residual paise")
        }

        return consumedValue
    }

    private func proratedValue(valuePaise: Int64,
                               consumedQuantity: ExactQuantity,
                               availableQuantity: ExactQuantity,
                               context: String) throws -> Int64 {
        let left = try CheckedMath.multiply(valuePaise, consumedQuantity.numerator, context: context)
        let numerator = try CheckedMath.multiply(left, availableQuantity.denominator, context: context)
        let denominator = try CheckedMath.multiply(availableQuantity.numerator, consumedQuantity.denominator, context: context)
        guard denominator > 0 else {
            throw AppError.businessRule("Arithmetic overflow while \(context).")
        }
        return numerator / denominator
    }
}
