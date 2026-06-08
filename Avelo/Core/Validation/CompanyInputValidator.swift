import Foundation

public struct CompanyInputValidator: Sendable {

    public struct Input: Sendable {
        public var name: String
        public var gstin: String?
        public var pan: String?

        public init(name: String, gstin: String?, pan: String?) {
            self.name = name
            self.gstin = gstin
            self.pan = pan
        }
    }

    public init() {}

    public func validate(_ input: Input) -> ValidationResult {
        var errors: [ValidationError] = []

        if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(ValidationError(
                code: .companyNameBlank,
                field: "name",
                message: "Company name is required."
            ))
        }

        if let gstin = input.gstin, !gstin.isEmpty {
            if !AccountInputValidator.isValidGSTIN(gstin) {
                errors.append(ValidationError(
                    code: .companyGstinInvalid,
                    field: "gstin",
                    message: "GSTIN is not in valid format."
                ))
            }
        }

        if let pan = input.pan, !pan.isEmpty {
            if !Self.isValidPAN(pan) {
                errors.append(ValidationError(
                    code: .companyPanInvalid,
                    field: "pan",
                    message: "PAN is not in valid format."
                ))
            }
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }

    public static func isValidPAN(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        let chars = Array(s)
        let validLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let validDigits = "0123456789"
        for i in 0...4 { if !validLetters.contains(chars[i]) { return false } }
        for i in 5...8 { if !validDigits.contains(chars[i]) { return false } }
        if !validLetters.contains(chars[9]) { return false }
        return true
    }
}
