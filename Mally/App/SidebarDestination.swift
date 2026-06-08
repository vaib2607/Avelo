import Foundation
import SwiftUI

public enum SidebarDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard
    case vouchers
    case accounts
    case reports
    case inventory
    case payroll
    case banking
    case audit
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .vouchers:  return "Vouchers"
        case .accounts:  return "Accounts"
        case .reports:   return "Reports"
        case .inventory: return "Inventory"
        case .payroll:   return "Payroll"
        case .banking:   return "Banking"
        case .audit:     return "Audit"
        case .settings:  return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .vouchers:  return "doc.text"
        case .accounts:  return "book"
        case .reports:   return "chart.bar"
        case .inventory: return "shippingbox"
        case .payroll:   return "person.3"
        case .banking:   return "building.columns"
        case .audit:     return "lock.shield"
        case .settings:  return "gear"
        }
    }

    public var shortcut: Character? {
        switch self {
        case .dashboard: return "1"
        case .vouchers:  return "2"
        case .accounts:  return "3"
        case .reports:   return "4"
        case .inventory, .payroll, .banking:
            return nil
        case .audit:     return "5"
        case .settings:  return "6"
        }
    }

    public var isV1Visible: Bool {
        switch self {
        case .inventory, .payroll, .banking:
            return false
        case .dashboard, .vouchers, .accounts, .reports, .audit, .settings:
            return true
        }
    }

    public static var v1VisibleCases: [SidebarDestination] {
        allCases.filter(\.isV1Visible)
    }
}
