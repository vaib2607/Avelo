import Foundation

/// One item row on a Tally item-invoice (Sales/Purchase). Persisted
/// separately from `avelo_ledger_lines` — the ledger lines produced by
/// posting (party, sales/purchase, duty) are what the rest of the app's
/// reports/reconciliation already understand; this table is the structured
/// record of what was actually invoiced, snapshotting the HSN/rate used at
/// posting time so later edits to the item master don't rewrite history.
public struct VoucherItemLine: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var voucherId: Voucher.ID
    public var itemId: InventoryItem.ID
    /// Canonical physical quantity snapshot. `quantity` remains a
    /// whole-unit compatibility accessor for older report/export callers.
    public var exactQuantity: ExactQuantity
    public var quantity: Int64 { exactQuantity.numerator }
    public var ratePaise: Int64
    public var taxableValuePaise: Int64
    public var hsnCode: String?
    public var gstRateBps: Int?
    public var cgstPaise: Int64
    public var sgstPaise: Int64
    public var igstPaise: Int64
    public var cessPaise: Int64
    public var lineOrder: Int
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                voucherId: Voucher.ID,
                itemId: InventoryItem.ID,
                quantity: ExactQuantity,
                ratePaise: Int64,
                taxableValuePaise: Int64,
                hsnCode: String? = nil,
                gstRateBps: Int? = nil,
                cgstPaise: Int64 = 0,
                sgstPaise: Int64 = 0,
                igstPaise: Int64 = 0,
                cessPaise: Int64 = 0,
                lineOrder: Int = 0,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.voucherId = voucherId
        self.itemId = itemId
        self.exactQuantity = quantity
        self.ratePaise = ratePaise
        self.taxableValuePaise = taxableValuePaise
        self.hsnCode = hsnCode
        self.gstRateBps = gstRateBps
        self.cgstPaise = cgstPaise
        self.sgstPaise = sgstPaise
        self.igstPaise = igstPaise
        self.cessPaise = cessPaise
        self.lineOrder = lineOrder
        self.createdAt = createdAt
    }

    public init(id: ID = UUID(),
                companyId: Company.ID,
                voucherId: Voucher.ID,
                itemId: InventoryItem.ID,
                quantity: Int64,
                ratePaise: Int64,
                taxableValuePaise: Int64,
                hsnCode: String? = nil,
                gstRateBps: Int? = nil,
                cgstPaise: Int64 = 0,
                sgstPaise: Int64 = 0,
                igstPaise: Int64 = 0,
                cessPaise: Int64 = 0,
                lineOrder: Int = 0,
                createdAt: Date = Date()) throws {
        self.init(id: id, companyId: companyId, voucherId: voucherId,
                       itemId: itemId,
                       quantity: try ExactQuantity(numerator: quantity, denominator: 1),
                       ratePaise: ratePaise, taxableValuePaise: taxableValuePaise,
                       hsnCode: hsnCode, gstRateBps: gstRateBps, cgstPaise: cgstPaise,
                       sgstPaise: sgstPaise, igstPaise: igstPaise, cessPaise: cessPaise,
                       lineOrder: lineOrder, createdAt: createdAt)
    }

    public var totalTaxPaise: Int64 {
        (try? CheckedMath.sum([cgstPaise, sgstPaise, igstPaise, cessPaise], context: "summing voucher item line tax")) ?? 0
    }

    public var invoiceValuePaise: Int64 {
        (try? CheckedMath.add(taxableValuePaise, totalTaxPaise, context: "summing voucher item line invoice value")) ?? 0
    }
}
