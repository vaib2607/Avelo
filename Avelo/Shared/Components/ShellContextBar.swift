import SwiftUI

public struct ShellContextBar: View {
    public let companyName: String?
    public let financialYearLabel: String?
    public let moduleTitle: String
    public let moduleHint: String

    public init(companyName: String?,
                financialYearLabel: String?,
                moduleTitle: String,
                moduleHint: String) {
        self.companyName = companyName
        self.financialYearLabel = financialYearLabel
        self.moduleTitle = moduleTitle
        self.moduleHint = moduleHint
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(companyName ?? "No company open")
                    .font(.headline)
                Text(financialYearLabel ?? "No financial year")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(moduleTitle)
                    .font(.headline)
                Text(moduleHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Label("1 Dashboard", systemImage: "1.circle")
                Label("2 Vouchers", systemImage: "2.circle")
                Label("3 Accounts", systemImage: "3.circle")
                Label("4 Reports", systemImage: "4.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
