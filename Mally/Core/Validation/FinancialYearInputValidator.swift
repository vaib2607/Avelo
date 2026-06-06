import Foundation

public struct FinancialYearInputValidator: Sendable {

    public struct Input: Sendable {
        public var label: String
        public var startDate: Date
        public var endDate: Date
        public var booksBeginDate: Date
        public var existingFinancialYearId: FinancialYear.ID?

        public init(label: String,
                    startDate: Date,
                    endDate: Date,
                    booksBeginDate: Date,
                    existingFinancialYearId: FinancialYear.ID? = nil) {
            self.label = label
            self.startDate = startDate
            self.endDate = endDate
            self.booksBeginDate = booksBeginDate
            self.existingFinancialYearId = existingFinancialYearId
        }
    }

    public init() {}

    public func validate(_ input: Input) -> ValidationResult {
        var errors: [ValidationError] = []

        if input.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(ValidationError(
                code: .financialYearZeroLength,
                field: "label",
                message: "Financial year label is required."
            ))
        }

        if input.endDate <= input.startDate {
            errors.append(ValidationError(
                code: .financialYearZeroLength,
                field: "endDate",
                message: "End date must be after start date."
            ))
        }

        if input.booksBeginDate < input.startDate {
            errors.append(ValidationError(
                code: .financialYearGapNotAllowed,
                field: "booksBeginDate",
                message: "Books begin date cannot be before financial year start."
            ))
        }
        if input.booksBeginDate > input.endDate {
            errors.append(ValidationError(
                code: .financialYearGapNotAllowed,
                field: "booksBeginDate",
                message: "Books begin date cannot be after financial year end."
            ))
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }
}
