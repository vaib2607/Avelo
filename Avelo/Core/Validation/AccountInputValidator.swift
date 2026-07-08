import Foundation

public struct AccountInputValidator: Sendable {

    public struct Input: Sendable {
        public var code: String
        public var name: String
        public var groupId: AccountGroup.ID?
        public var openingBalancePaise: Int64
        public var openingBalanceSide: OpeningBalanceSide
        public var gstin: String?
        public var existingAccountId: Account.ID?

        public init(code: String,
                    name: String,
                    groupId: AccountGroup.ID?,
                    openingBalancePaise: Int64,
                    openingBalanceSide: OpeningBalanceSide = .debit,
                    gstin: String?,
                    existingAccountId: Account.ID?) {
            self.code = code
            self.name = name
            self.groupId = groupId
            self.openingBalancePaise = openingBalancePaise
            self.openingBalanceSide = openingBalanceSide
            self.gstin = gstin
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

    public static func isValidGSTIN(_ s: String) -> Bool {
        guard s.count == 15 else { return false }
        let chars = Array(s)
        let validLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let validDigits = "0123456789"
        func isLetter(_ c: Character) -> Bool { validLetters.contains(c) }
        func isDigit(_ c: Character) -> Bool { validDigits.contains(c) }
        func isAlphanumeric(_ c: Character) -> Bool { isLetter(c) || isDigit(c) }
        // 2-digit state code
        for i in 0...1 { if !isDigit(chars[i]) { return false } }
        // 10-char PAN: 5 letters, 4 digits, 1 letter
        for i in 2...6 { if !isLetter(chars[i]) { return false } }
        for i in 7...10 { if !isDigit(chars[i]) { return false } }
        if !isLetter(chars[11]) { return false }
        // entity code (digit)
        if !isDigit(chars[12]) { return false }
        // default 'Z'
        if !isLetter(chars[13]) { return false }
        // checksum digit, alphanumeric
        if !isAlphanumeric(chars[14]) { return false }
        return true
    }
}
