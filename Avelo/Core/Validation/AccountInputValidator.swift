import Foundation

public struct AccountInputValidator: Sendable {

    public struct Input: Sendable {
        public var code: String
        public var name: String
        public var groupId: AccountGroup.ID?
        public var openingBalancePaise: Int64
        public var openingBalanceSide: OpeningBalanceSide
        public var gstin: String?
        public var mailingName: String?
        public var mailingAddress: String?
        public var stateCode: String?
        public var country: String?
        public var gstRegistrationType: GSTRegistrationType?
        public var maintainBillwise: Bool
        public var creditPeriodDays: Int?
        public var existingAccountId: Account.ID?

        public init(code: String,
                    name: String,
                    groupId: AccountGroup.ID?,
                    openingBalancePaise: Int64,
                    openingBalanceSide: OpeningBalanceSide = .debit,
                    gstin: String?,
                    mailingName: String? = nil,
                    mailingAddress: String? = nil,
                    stateCode: String? = nil,
                    country: String? = nil,
                    gstRegistrationType: GSTRegistrationType? = nil,
                    maintainBillwise: Bool = false,
                    creditPeriodDays: Int? = nil,
                    existingAccountId: Account.ID?) {
            self.code = code
            self.name = name
            self.groupId = groupId
            self.openingBalancePaise = openingBalancePaise
            self.openingBalanceSide = openingBalanceSide
            self.gstin = gstin
            self.mailingName = mailingName
            self.mailingAddress = mailingAddress
            self.stateCode = stateCode
            self.country = country
            self.gstRegistrationType = gstRegistrationType
            self.maintainBillwise = maintainBillwise
            self.creditPeriodDays = creditPeriodDays
            self.existingAccountId = existingAccountId
        }
    }

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func validate(_ input: Input, companyId: Company.ID) -> ValidationResult {
        var errors: [ValidationError] = []

        let trimmedCode = input.code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCode.isEmpty {
            errors.append(ValidationError(
                code: .accountNameBlank,
                field: "code",
                message: "Account code is required."
            ))
        } else if !isAlphanumericOrUnderscore(trimmedCode) {
            errors.append(ValidationError(
                code: .accountNameBlank,
                field: "code",
                message: "Account code may only contain letters, digits, and underscore."
            ))
        } else {
            do {
                let existing: Int64? = try db.queryOne(
                    "SELECT COUNT(*) FROM avelo_accounts WHERE company_id = ? AND code = ? AND id != ?",
                    bind: [
                        .text(companyId.uuidString),
                        .text(trimmedCode),
                        .text(input.existingAccountId?.uuidString ?? "")
                    ]
                ) { r in r.int(0) }
                if (existing ?? 0) > 0 {
                    errors.append(ValidationError(
                        code: .accountCodeDuplicate,
                        field: "code",
                        message: "An account with this code already exists."
                    ))
                }
            } catch {
                errors.append(ValidationError(
                    code: .internal,
                    field: "code",
                    message: "Unable to validate account code uniqueness."
                ))
            }
        }

        if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(ValidationError(
                code: .accountNameBlank,
                field: "name",
                message: "Account name is required."
            ))
        }

        if input.groupId == nil {
            errors.append(ValidationError(
                code: .accountGroupRequired,
                field: "group",
                message: "Please choose a group."
            ))
        }

        if let gstin = input.gstin, !gstin.isEmpty {
            if !Self.isValidGSTIN(gstin) {
                errors.append(ValidationError(
                    code: .companyGstinInvalid,
                    field: "gstin",
                    message: "GSTIN is not in valid format."
                ))
            }
        }

        if let state = input.stateCode, !state.isEmpty, GSTStateCode.table[state] == nil {
            errors.append(ValidationError(
                code: .companyGstinInvalid,
                field: "stateCode",
                message: "State code is not a valid GST state code."
            ))
        }

        if let days = input.creditPeriodDays, days < 0 {
            errors.append(ValidationError(
                code: .accountOpeningBalanceRequired,
                field: "creditPeriodDays",
                message: "Credit period cannot be negative."
            ))
        }

        if input.openingBalancePaise < 0 {
            errors.append(ValidationError(
                code: .accountOpeningBalanceRequired,
                field: "openingBalance",
                message: "Opening balance cannot be negative."
            ))
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }

    private func isAlphanumericOrUnderscore(_ s: String) -> Bool {
        for c in s {
            if !(c.isLetter || c.isNumber || c == "_") { return false }
        }
        return true
    }

    /// Validates a 15-character GSTIN: statutory state code (positions 1–2),
    /// embedded PAN (3–12: five letters, four digits, one letter), entity
    /// code (13, '0' not permitted), literal 'Z' (14), and the official
    /// mod-36 check digit (15).
    public static func isValidGSTIN(_ s: String) -> Bool {
        let chars = Array(s)
        guard chars.count == 15 else { return false }
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let digits = "0123456789"
        func isLetter(_ c: Character) -> Bool { letters.contains(c) }
        func isDigit(_ c: Character) -> Bool { digits.contains(c) }

        // 1–2: state code must exist in the statutory table.
        guard GSTStateCode.table[String(chars[0...1])] != nil else { return false }
        // 3–12: PAN — 5 letters, 4 digits, 1 letter.
        for i in 2...6 { if !isLetter(chars[i]) { return false } }
        for i in 7...10 { if !isDigit(chars[i]) { return false } }
        if !isLetter(chars[11]) { return false }
        // 13: entity number — alphanumeric, '0' not permitted.
        if !(isLetter(chars[12]) || (isDigit(chars[12]) && chars[12] != "0")) { return false }
        // 14: always 'Z'.
        if chars[13] != "Z" { return false }

        // 15: mod-36 check digit over the first 14 characters.
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var sum = 0
        for (i, c) in chars.prefix(14).enumerated() {
            guard let v = alphabet.firstIndex(of: c) else { return false }
            let hash = v * (i % 2 == 0 ? 1 : 2)
            sum += hash / 36 + hash % 36
        }
        return alphabet[(36 - sum % 36) % 36] == chars[14]
    }
}
