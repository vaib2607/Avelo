import Foundation

struct BillAllocationEvent: Sendable {
    let allocation: BillAllocation
    let voucherId: Voucher.ID
    let accountId: Account.ID
    let partyName: String
    let voucherNumber: String
    let voucherDate: Date
    let voucherCreatedAt: Date
    let signedPaise: Int64
}

struct BillOutstandingItem: Sendable, Hashable {
    let id: String
    let accountId: Account.ID
    let partyName: String
    let referenceNumber: String
    let sourceKind: BillAllocationKind
    let sourceVoucherId: Voucher.ID
    let sourceVoucherNumber: String
    let originDate: Date
    var remainingPaise: Int64
}

enum BillAllocationEngine {
    static func settle(events: [BillAllocationEvent], asOfDate: Date) throws -> [BillOutstandingItem] {
        var openItems: [BillOutstandingItem] = []

        for event in events.sorted(by: eventSort) {
            switch event.allocation.kind {
            case .newRef:
                try applyNewReference(event, openItems: &openItems)
            case .agstRef:
                try applyAgainstReference(event, openItems: &openItems)
            case .advance, .onAccount:
                try applyOpenAmount(event, openItems: &openItems, referenceNumber: event.allocation.referenceNumber ?? event.voucherNumber)
            }
        }

        return openItems
            .filter { $0.remainingPaise != 0 && $0.originDate <= asOfDate }
            .sorted { lhs, rhs in
                if lhs.accountId != rhs.accountId { return lhs.accountId.uuidString < rhs.accountId.uuidString }
                if lhs.originDate != rhs.originDate { return lhs.originDate < rhs.originDate }
                return lhs.referenceNumber < rhs.referenceNumber
            }
    }

    private static func eventSort(_ lhs: BillAllocationEvent, _ rhs: BillAllocationEvent) -> Bool {
        if lhs.voucherDate != rhs.voucherDate { return lhs.voucherDate < rhs.voucherDate }
        if lhs.voucherCreatedAt != rhs.voucherCreatedAt { return lhs.voucherCreatedAt < rhs.voucherCreatedAt }
        if lhs.voucherNumber != rhs.voucherNumber { return lhs.voucherNumber < rhs.voucherNumber }
        return lhs.allocation.id.uuidString < rhs.allocation.id.uuidString
    }

    private static func applyNewReference(_ event: BillAllocationEvent,
                                          openItems: inout [BillOutstandingItem]) throws {
        let referenceNumber = event.allocation.referenceNumber ?? event.voucherNumber
        var remaining = event.signedPaise
        remaining = try consumeAgainstOpposite(
            remaining: remaining,
            openItems: &openItems,
            preferredReference: nil,
            accountId: event.accountId
        )
        guard remaining != 0 else { return }
        openItems.append(
            BillOutstandingItem(
                id: event.allocation.id.uuidString,
                accountId: event.accountId,
                partyName: event.partyName,
                referenceNumber: referenceNumber,
                sourceKind: .newRef,
                sourceVoucherId: event.voucherId,
                sourceVoucherNumber: event.voucherNumber,
                originDate: event.voucherDate,
                remainingPaise: remaining
            )
        )
    }

    private static func applyAgainstReference(_ event: BillAllocationEvent,
                                              openItems: inout [BillOutstandingItem]) throws {
        guard let referenceNumber = event.allocation.referenceNumber, !referenceNumber.isEmpty else {
            throw AppError.businessRule("Against Ref allocation requires a reference number.")
        }
        let remaining = try consumeAgainstOpposite(
            remaining: event.signedPaise,
            openItems: &openItems,
            preferredReference: referenceNumber,
            accountId: event.accountId
        )
        guard remaining == 0 else {
            throw AppError.businessRule("Against Ref allocation exceeds the open amount for reference \(referenceNumber).")
        }
    }

    private static func applyOpenAmount(_ event: BillAllocationEvent,
                                        openItems: inout [BillOutstandingItem],
                                        referenceNumber: String) throws {
        var remaining = event.signedPaise
        remaining = try consumeAgainstOpposite(
            remaining: remaining,
            openItems: &openItems,
            preferredReference: nil,
            accountId: event.accountId
        )
        guard remaining != 0 else { return }
        openItems.append(
            BillOutstandingItem(
                id: event.allocation.id.uuidString,
                accountId: event.accountId,
                partyName: event.partyName,
                referenceNumber: referenceNumber,
                sourceKind: event.allocation.kind,
                sourceVoucherId: event.voucherId,
                sourceVoucherNumber: event.voucherNumber,
                originDate: event.voucherDate,
                remainingPaise: remaining
            )
        )
    }

    private static func consumeAgainstOpposite(remaining: Int64,
                                               openItems: inout [BillOutstandingItem],
                                               preferredReference: String?,
                                               accountId: Account.ID) throws -> Int64 {
        var remaining = remaining
        for index in openItems.indices {
            guard remaining != 0 else { break }
            guard openItems[index].accountId == accountId else { continue }
            guard preferredReference == nil || openItems[index].referenceNumber == preferredReference else { continue }
            guard signum(remaining) != signum(openItems[index].remainingPaise) else { continue }

            let remainingMagnitude = try CheckedMath.abs(remaining, context: "calculating bill settlement remaining magnitude")
            let openMagnitude = try CheckedMath.abs(openItems[index].remainingPaise, context: "calculating bill settlement open magnitude")
            let consumed = min(remainingMagnitude, openMagnitude)
            let signedConsumed = try CheckedMath.multiply(consumed, signum(remaining), context: "calculating signed bill settlement consumption")
            remaining = try CheckedMath.subtract(remaining, signedConsumed, context: "reducing bill settlement remainder")
            openItems[index].remainingPaise = try CheckedMath.add(openItems[index].remainingPaise, signedConsumed, context: "reducing bill outstanding item")
        }
        openItems.removeAll { $0.remainingPaise == 0 }
        return remaining
    }

    private static func signum(_ value: Int64) -> Int64 {
        if value == 0 { return 0 }
        return value > 0 ? 1 : -1
    }
}
