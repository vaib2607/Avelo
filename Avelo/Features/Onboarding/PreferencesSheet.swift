import SwiftUI

public struct PreferencesSheet: View {

    @Environment(AppRouter.self) private var router
    @AppStorage("avelo.prefs.dateFormat") private var dateFormat: String = "dd/MM/yyyy"
    @AppStorage("avelo.prefs.currencyLocale") private var currencyLocale: String = "en_IN"
    @AppStorage("avelo.prefs.confirmBeforePost") private var confirmPost: Bool = true
    @AppStorage("avelo.prefs.confirmBeforeDelete") private var confirmDelete: Bool = true

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences").font(.title2.bold())
            Form {
                Picker("Date format", selection: $dateFormat) {
                    Text("dd/MM/yyyy").tag("dd/MM/yyyy")
                    Text("yyyy-MM-dd").tag("yyyy-MM-dd")
                }
                Picker("Currency grouping", selection: $currencyLocale) {
                    Text("Indian (1,18,000.00)").tag("en_IN")
                    Text("Western (118,000.00)").tag("en_US")
                }
                Toggle("Confirm before posting vouchers", isOn: $confirmPost)
                Toggle("Confirm before reversing vouchers", isOn: $confirmDelete)
            }
            .formStyle(.grouped)
            Spacer()
            HStack {
                Spacer()
                Button("Close") { router.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 360)
    }
}
