import SwiftUI

public struct ImportStatementSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    let companyId: Company.ID
    let db: SQLiteDatabase
    let accounts: [Account]

    @State private var accountId: Account.ID?
    @State private var csvText: String = ""
    @State private var status: String = ""
    @State private var isWorking: Bool = false

    public init(companyId: Company.ID, db: SQLiteDatabase, accounts: [Account]) {
        self.companyId = companyId
        self.db = db
        self.accounts = accounts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Import Bank Statement").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                Picker("Account", selection: $accountId) {
                    Text("Select…").tag(Account.ID?.none)
                    ForEach(accounts) { a in
                        Text("\(a.code) — \(a.name)").tag(Optional(a.id))
                    }
                }
                Text("Paste CSV with columns: date,amount,narration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $csvText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
            }
            .formStyle(.grouped)
            if !status.isEmpty {
                Text(status).foregroundStyle(.secondary).padding(12)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Import") { import_() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(accountId == nil || csvText.isEmpty || isWorking)
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 520)
        .onAppear { if accountId == nil { accountId = accounts.first?.id } }
    }

    private func import_() {
        guard let aid = accountId else { return }
        isWorking = true
        status = "Parsing…"
        let parsed = BankStatementCSVParser.parse(csvText, companyId: companyId, accountId: aid)
        let entries = parsed.entries
        guard !entries.isEmpty else {
            status = parsed.errors.isEmpty ? "No rows found." : parsed.errors.joined(separator: "\n")
            isWorking = false
            return
        }
        do {
            try BankReconciliationService(db: db, companyId: companyId)
                .importStatement(accountId: aid, entries: entries)
            if parsed.errors.isEmpty {
                status = "Imported \(entries.count) entries."
            } else {
                status = "Imported \(entries.count) entries. Skipped \(parsed.errors.count) row(s):\n\(parsed.errors.joined(separator: "\n"))"
            }
            env.showSuccess("Statement imported.")
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        isWorking = false
    }
}

public struct BankStatementCSVParser: Sendable {
    public struct Result: Sendable, Equatable {
        public let entries: [BankReconciliationService.StatementEntry]
        public let errors: [String]
    }

    public static func parse(_ csvText: String,
                             companyId: Company.ID,
                             accountId: Account.ID) -> Result {
        let lines = csvText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var entries: [BankReconciliationService.StatementEntry] = []
        var errors: [String] = []
        let iso = DateFormatters.isoDate

        for (idx, raw) in lines.enumerated() {
            let rowNumber = idx + 1
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if idx == 0 && trimmed.lowercased().contains("date") { continue }

            let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else {
                errors.append("Row \(rowNumber): expected date, amount, narration.")
                continue
            }
            guard let date = iso.date(from: parts[0]) else {
                errors.append("Row \(rowNumber): invalid date '\(parts[0])'.")
                continue
            }
            guard let parsedAmountPaise = Currency.parseRupeeInput(parts[1]) else {
                errors.append("Row \(rowNumber): invalid amount '\(parts[1])'.")
                continue
            }
            let amountPaise = parts[1].hasPrefix("-") ? -abs(parsedAmountPaise) : parsedAmountPaise
            let narration = parts[2...].joined(separator: ",").trimmingCharacters(in: .whitespaces)
            guard !narration.isEmpty else {
                errors.append("Row \(rowNumber): narration is required.")
                continue
            }
            entries.append(BankReconciliationService.StatementEntry(
                id: UUID(),
                companyId: companyId,
                accountId: accountId,
                date: date,
                amountPaise: amountPaise,
                narration: narration,
                isCleared: false
            ))
        }
        return Result(entries: entries, errors: errors)
    }
}
