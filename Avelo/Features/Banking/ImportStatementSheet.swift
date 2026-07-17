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
        let lines = csvText.split(separator: "\n").map(String.init)
        var entries: [BankReconciliationService.StatementEntry] = []
        let iso = DateFormatters.isoDate
        for (idx, raw) in lines.enumerated() {
            if idx == 0 && raw.lowercased().contains("date") { continue }
            let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { continue }
            guard let d = iso.date(from: parts[0]) else { continue }
            guard let paise = Currency.parseRupeeInput(parts[1]) else { continue }
            let narration = parts[2...].joined(separator: ",")
            entries.append(BankReconciliationService.StatementEntry(
                id: UUID(),
                accountId: aid,
                date: d,
                amountPaise: paise,
                narration: narration,
                isCleared: false
            ))
        }
        do {
            try BankReconciliationService(db: db, companyId: companyId)
                .importStatement(accountId: aid, entries: entries)
            status = "Imported \(entries.count) entries."
            env.showSuccess("Statement imported.")
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        isWorking = false
    }
}
