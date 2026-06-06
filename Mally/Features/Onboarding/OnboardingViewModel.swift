import SwiftUI
import AppKit

@MainActor
public final class OnboardingViewModel: ObservableObject {

    @Published public var companyName: String = ""
    @Published public var pan: String = ""
    @Published public var gstin: String = ""
    @Published public var fyLabel: String = ""
    @Published public var fyStart: Date = IndianFinancialYear.start(for: Date())
    @Published public var fyEnd: Date = IndianFinancialYear.end(for: Date())
    @Published public var booksBegin: Date = IndianFinancialYear.start(for: Date())
    @Published public var enableInventory: Bool = false
    @Published public var inventoryMode: InventoryLinkMode = .autoPrompt
    @Published public var canCreate: Bool = false

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
