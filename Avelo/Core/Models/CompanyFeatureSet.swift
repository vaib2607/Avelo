import Foundation

/// Per-company capability flags (the F11-equivalent). One value derived from
/// the company row and cached on `CompanyContext`; every UI gate reads this
/// instead of re-reading `Company` from the database.
///
/// Only `inventory` is persisted today (`avelo_companies.is_inventory_enabled`).
/// The remaining capabilities have no toggle UI and no persisted column yet —
/// they default to enabled so that modules which are always-on today (GST,
/// payroll, banking, cost) keep behaving identically. Persist a flag only in
/// the slice that ships its Settings toggle, not before.
public struct CompanyFeatureSet: Hashable, Sendable {
    public var inventory: Bool
    public var billWise: Bool
    public var cost: Bool
    public var gst: Bool
    public var payroll: Bool
    public var banking: Bool
    public var orders: Bool
    public var batchesGodowns: Bool
    public var manufacturing: Bool
    public var budgets: Bool
    public var interest: Bool

    public init(inventory: Bool = false,
                billWise: Bool = true,
                cost: Bool = true,
                gst: Bool = true,
                payroll: Bool = true,
                banking: Bool = true,
                orders: Bool = true,
                batchesGodowns: Bool = true,
                manufacturing: Bool = true,
                budgets: Bool = true,
                interest: Bool = true) {
        self.inventory = inventory
        self.billWise = billWise
        self.cost = cost
        self.gst = gst
        self.payroll = payroll
        self.banking = banking
        self.orders = orders
        self.batchesGodowns = batchesGodowns
        self.manufacturing = manufacturing
        self.budgets = budgets
        self.interest = interest
    }

    /// No company open: inventory hidden, everything else enabled — matches
    /// the router's pre-existing closed-company behavior.
    public static let defaults = CompanyFeatureSet()

    public init(company: Company) {
        self.init(inventory: company.isInventoryEnabled)
    }
}
