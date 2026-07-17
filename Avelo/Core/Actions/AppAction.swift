import SwiftUI

/// Stable identifier for a Create/Display/Alter/Duplicate/Reverse/Export/
/// Drill-Down action on one of the migrated object types (Account, Voucher,
/// Trial Balance, Day Book). Kept small and explicit rather than generic
/// (`AppActionID.create(.account)`) so each case can carry only the payload
/// it actually needs (e.g. voucher creation needs the type code).
public enum AppActionID: Hashable, Sendable {
    case accountsDisplay
    case accountCreate
    case accountAlter
    case accountDrillDown

    case vouchersDisplay
    case voucherCreate(VoucherType.Code)
    case voucherAlter
    case voucherDuplicate
    case voucherReverse
    case voucherExportPDF

    case trialBalanceDisplay
    case dayBookDisplay
}

/// Everything an action's availability check or effect closure needs. Only
/// carries the fields actions in this slice actually read — add fields when
/// a migrated action needs one, not speculatively.
public struct AppActionContext: Sendable {
    public var companyContext: CompanyContext?
    public var voucher: Voucher?
    public var accountId: Account.ID?

    public init(companyContext: CompanyContext? = nil, voucher: Voucher? = nil, accountId: Account.ID? = nil) {
        self.companyContext = companyContext
        self.voucher = voucher
        self.accountId = accountId
    }
}

/// Mirrors `AccountEligibility`'s `isEligible`/`rejectionReason` shape
/// (`Avelo/Core/Validation/AccountEligibilityPolicy.swift`) for consistency
/// across the codebase's two "is this allowed, and why not" types.
public struct AppActionAvailability: Sendable, Equatable {
    public let isAvailable: Bool
    public let rejectionReason: String?

    public init(isAvailable: Bool, rejectionReason: String? = nil) {
        self.isAvailable = isAvailable
        self.rejectionReason = rejectionReason
    }

    public static let available = AppActionAvailability(isAvailable: true)

    public static func unavailable(_ reason: String) -> AppActionAvailability {
        AppActionAvailability(isAvailable: false, rejectionReason: reason)
    }
}

/// Router-facing effect of a successful action. `AppActionResult` carries
/// this instead of touching `AppRouter` directly so the action layer stays
/// UI-framework-agnostic; callers hand the effect to `AppActionRegistry.apply`.
public enum AppActionEffect: Sendable {
    case go(SidebarDestination)
    case present(RouterSheet)
    case openReport(ReportSelection)
    case openLedger(Account.ID)
    case none
}

public struct AppActionResult: Sendable {
    public let succeeded: Bool
    public let effect: AppActionEffect
    public let rejectionReason: String?
}

/// One catalog entry. `key`/`modifiers` are optional because not every
/// action has a global keyboard shortcut (e.g. row-only actions like
/// Duplicate/Export today have no keyboard binding).
public struct AppAction {
    public let id: AppActionID
    public let title: String
    public let symbol: String
    public let key: KeyEquivalent?
    public let modifiers: EventModifiers
    /// Text shown in the shortcut-help sheet and command palette subtitle
    /// (e.g. "F4", "⇧⌘A"). `nil` when there's no chord to show.
    public let shortcutLabel: String?
    /// `nil` means this action does not appear in the command palette,
    /// matching today's behavior where Trial Balance/Day Book aren't listed.
    public let paletteSubtitle: String?
    public let availability: @Sendable (AppActionContext) -> AppActionAvailability
    public let effect: @Sendable (AppActionContext) -> AppActionEffect

    public init(
        id: AppActionID,
        title: String,
        symbol: String,
        key: KeyEquivalent? = nil,
        modifiers: EventModifiers = [],
        shortcutLabel: String? = nil,
        paletteSubtitle: String? = nil,
        availability: @escaping @Sendable (AppActionContext) -> AppActionAvailability = { _ in .available },
        effect: @escaping @Sendable (AppActionContext) -> AppActionEffect
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.key = key
        self.modifiers = modifiers
        self.shortcutLabel = shortcutLabel
        self.paletteSubtitle = paletteSubtitle
        self.availability = availability
        self.effect = effect
    }

    /// Checks availability, then produces a result carrying either the
    /// action's effect or a rejection reason. Unavailable actions never
    /// produce an effect, whether called from a UI control or directly
    /// (e.g. via keyboard dispatch) — the check isn't just a hidden button.
    public func perform(_ context: AppActionContext) -> AppActionResult {
        let result = availability(context)
        guard result.isAvailable else {
            return AppActionResult(succeeded: false, effect: .none, rejectionReason: result.rejectionReason)
        }
        return AppActionResult(succeeded: true, effect: effect(context), rejectionReason: nil)
    }
}
