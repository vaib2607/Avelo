import SwiftUI

public struct AccountPicker: View {
    @Binding public var selection: Account.ID?
    public var accounts: [Account]
    public var placeholder: String = "Choose account…"
    public var filter: ((Account) -> Bool)? = nil
    public var isEditable: Bool = true

    public init(selection: Binding<Account.ID?>,
                accounts: [Account],
                placeholder: String = "Choose account…",
                filter: ((Account) -> Bool)? = nil,
                isEditable: Bool = true) {
        self._selection = selection
        self.accounts = accounts
        self.placeholder = placeholder
        self.filter = filter
        self.isEditable = isEditable
    }

    public var body: some View {
        Picker("", selection: $selection) {
            Text(placeholder).tag(Account.ID?.none)
            ForEach(filtered) { account in
                Text("\(account.code)  —  \(account.name)").tag(Account.ID?.some(account.id))
            }
        }
        .labelsHidden()
        .disabled(!isEditable || filtered.isEmpty)
    }

    private var filtered: [Account] {
        let base = filter.map { f in accounts.filter(f) } ?? accounts
        return base.sorted { lhs, rhs in
            if lhs.code == rhs.code { return lhs.name < rhs.name }
            return lhs.code < rhs.code
        }
    }
}
