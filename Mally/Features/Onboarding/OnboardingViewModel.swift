import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
public final class OnboardingViewModel {

    public var companyName: String = ""
    public var pan: String = ""
    public var gstin: String = ""
    public var fyLabel: String = ""
    public var fyStart: Date = IndianFinancialYear.start(for: Date())
    public var fyEnd: Date = IndianFinancialYear.end(for: Date())
    public var booksBegin: Date = IndianFinancialYear.start(for: Date())
    public var enableInventory: Bool = false
    public var inventoryMode: InventoryLinkMode = .autoPrompt
    public var canCreate: Bool = false

    public init() {
        let fy = IndianFinancialYear.detect()
        self.fyLabel = fy.label
        self.fyStart = fy.start
        self.fyEnd = fy.end
        self.booksBegin = fy.start
    }

    public func refreshValidity() {
        let company = CompanyInputValidator.Input(name: companyName, gstin: gstin, pan: pan)
        let fy = FinancialYearInputValidator.Input(
            label: fyLabel, startDate: fyStart, endDate: fyEnd, booksBeginDate: booksBegin
        )
        let v1 = CompanyInputValidator().validate(company)
        let v2 = FinancialYearInputValidator().validate(fy)
        canCreate = true
        if case .invalid = v1 { canCreate = false }
        if case .invalid = v2 { canCreate = false }
    }
}
