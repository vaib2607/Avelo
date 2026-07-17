import SwiftUI

/// Single source of truth for the Create/Display/Alter/Duplicate/Reverse/
/// Export/Drill-Down actions on Accounts, Vouchers, Trial Balance, and Day
/// Book. Menu commands, toolbar buttons, the command palette, keyboard
/// dispatch, row actions, and the shortcut-help sheet all read from here
/// instead of each independently declaring the same title/shortcut/gating.
///
/// Availability only encodes gates that already exist at today's call sites
/// (e.g. Reverse/Edit disabled for reversal vouchers, Duplicate/Export
/// disabled for voucher types with no "New X" sheet). Fiscal-year lock is
/// enforced at save time by `VoucherDraftValidator`/`FiscalLockChecker`, not
/// by any of the migrated menu/toolbar/palette/keyboard call sites today —
/// wiring it in here would change behavior (shortcuts and menu items that
/// currently always open their sheet), so it's left alone.
public enum AppActionRegistry {

    public static let actions: [AppAction] = [
        .init(
            id: .accountsDisplay,
            title: "Accounts",
            symbol: "book",
            key: "3", modifiers: .command,
            shortcutLabel: "⌘3",
            effect: { _ in .go(.accounts) }
        ),
        .init(
            id: .accountCreate,
            title: "New Account",
            symbol: "plus.circle",
            key: "a", modifiers: [.command, .shift],
            shortcutLabel: "⇧⌘A",
            paletteSubtitle: "Create",
            effect: { _ in .present(.newAccount) }
        ),
        .init(
            id: .accountAlter,
            title: "Edit",
            symbol: "pencil",
            availability: { ctx in
                ctx.accountId != nil ? .available : .unavailable("No account selected.")
            },
            effect: { ctx in ctx.accountId.map { .present(.editAccount($0)) } ?? .none }
        ),
        .init(
            id: .accountDrillDown,
            title: "Ledger",
            symbol: "list.bullet.rectangle",
            availability: { ctx in
                ctx.accountId != nil ? .available : .unavailable("No account selected.")
            },
            effect: { ctx in ctx.accountId.map { .openLedger($0) } ?? .none }
        ),

        .init(
            id: .vouchersDisplay,
            title: "Vouchers",
            symbol: "doc.text",
            key: "2", modifiers: .command,
            shortcutLabel: "⌘2",
            effect: { _ in .go(.vouchers) }
        ),

        .init(
            id: .voucherAlter,
            title: "Edit",
            symbol: "pencil",
            availability: { ctx in
                guard let v = ctx.voucher else { return .unavailable("No voucher selected.") }
                return v.isReversal ? .unavailable("Reversal vouchers cannot be edited.") : .available
            },
            effect: { ctx in ctx.voucher.map { .present(.editVoucher($0.id)) } ?? .none }
        ),
        .init(
            id: .voucherReverse,
            title: "Reverse",
            symbol: "arrow.uturn.backward",
            availability: { ctx in
                guard let v = ctx.voucher else { return .unavailable("No voucher selected.") }
                return v.isReversal ? .unavailable("Reversal vouchers cannot be reversed.") : .available
            },
            effect: { ctx in ctx.voucher.map { .present(.reverseVoucher($0.id)) } ?? .none }
        ),
        .init(
            id: .voucherDuplicate,
            title: "Duplicate",
            symbol: "doc.on.doc",
            availability: { ctx in
                guard let v = ctx.voucher else { return .unavailable("No voucher selected.") }
                return creationSheet(for: v.voucherTypeCode) != nil
                    ? .available
                    : .unavailable("This voucher type can't be duplicated.")
            },
            // Duplicating needs to load the source voucher's lines and stage
            // draft recovery — call-site logic beyond a router effect. The
            // registry just gates whether it's allowed; VouchersView keeps
            // performing it.
            effect: { _ in .none }
        ),
        .init(
            id: .voucherExportPDF,
            title: "Export PDF…",
            symbol: "arrow.down.doc",
            availability: { ctx in
                guard let v = ctx.voucher else { return .unavailable("No voucher selected.") }
                return (v.voucherTypeCode == .sales || v.voucherTypeCode == .purchase)
                    ? .available
                    : .unavailable("Only Sales and Purchase vouchers export as PDF.")
            },
            effect: { _ in .none }
        ),

        .init(
            id: .trialBalanceDisplay,
            title: "Trial Balance",
            symbol: "chart.bar",
            key: "1", modifiers: [.command, .option],
            shortcutLabel: "⌘⌥1",
            effect: { _ in .openReport(.trialBalance) }
        ),
        .init(
            id: .dayBookDisplay,
            title: "Day Book",
            symbol: "calendar",
            key: "5", modifiers: [.command, .option],
            shortcutLabel: "⌘⌥5",
            effect: { _ in .openReport(.dayBook) }
        ),
    ] + VoucherType.Code.creatable.map(voucherCreateAction)

    private static let byId: [AppActionID: AppAction] = Dictionary(
        uniqueKeysWithValues: actions.map { ($0.id, $0) }
    )

    public static func action(for id: AppActionID) -> AppAction? {
        byId[id]
    }

    public static func availability(for id: AppActionID, in context: AppActionContext) -> AppActionAvailability {
        action(for: id)?.availability(context) ?? .unavailable("Unknown action.")
    }

    /// Applies a successful result's effect to the router. Unavailable
    /// results (`succeeded == false`) are no-ops — callers that want to
    /// surface the rejection reason read `result.rejectionReason` themselves.
    @MainActor
    @discardableResult
    public static func apply(_ result: AppActionResult, router: AppRouter) -> Bool {
        guard result.succeeded else { return false }
        switch result.effect {
        case .go(let destination): router.go(destination)
        case .present(let sheet): router.present(sheet)
        case .openReport(let report): router.openReport(report)
        case .openLedger(let accountId): router.openLedger(accountId)
        case .none: break
        }
        return true
    }

    /// Look up, gate, and apply an action's effect in one call — the shape
    /// every call site (menu, toolbar, palette, keyboard dispatch) uses.
    @MainActor
    @discardableResult
    public static func perform(_ id: AppActionID, context: AppActionContext = AppActionContext(), router: AppRouter) -> AppActionResult {
        guard let action = action(for: id) else {
            return AppActionResult(succeeded: false, effect: .none, rejectionReason: "Unknown action.")
        }
        let result = action.perform(context)
        apply(result, router: router)
        return result
    }

    /// The "New X" sheet for a voucher type, or `nil` for system-generated
    /// types with no creation UI. Shared by voucher-create actions and the
    /// Duplicate gate.
    static func creationSheet(for type: VoucherType.Code) -> RouterSheet? {
        switch type {
        case .journal: return .newJournal
        case .payment: return .newPayment
        case .receipt: return .newReceipt
        case .contra: return .newContra
        case .purchase: return .newPurchase
        case .sales: return .newSales
        case .creditNote: return .newCreditNote
        case .debitNote: return .newDebitNote
        case .opening, .payroll: return nil
        }
    }

    private static func voucherCreateAction(_ type: VoucherType.Code) -> AppAction {
        AppAction(
            id: .voucherCreate(type),
            title: "New \(type.displayName)",
            symbol: "plus.rectangle",
            shortcutLabel: type.functionKeyLabel,
            paletteSubtitle: "Voucher · \(type.functionKeyLabel ?? type.rawValue)",
            effect: { _ in creationSheet(for: type).map { .present($0) } ?? .none }
        )
    }
}

private extension VoucherType.Code {
    /// The 8 types with a "New X" sheet, in the order menus/palette list them.
    static let creatable: [VoucherType.Code] = [.contra, .payment, .receipt, .journal, .sales, .purchase, .creditNote, .debitNote]

    var functionKeyLabel: String? {
        switch self {
        case .contra: return "F4"
        case .payment: return "F5"
        case .receipt: return "F6"
        case .journal: return "F7"
        case .sales: return "F8"
        case .purchase: return "F9"
        case .creditNote: return "⌃F8"
        case .debitNote: return "⌃F9"
        case .opening, .payroll: return nil
        }
    }
}
