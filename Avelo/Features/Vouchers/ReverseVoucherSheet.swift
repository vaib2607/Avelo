import SwiftUI

public struct ReverseVoucherSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    let voucherId: Voucher.ID
    @State private var reason: String = ""

    public init(voucherId: Voucher.ID) {
        self.voucherId = voucherId
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Reverse Voucher").font(.title2.bold())
                Spacer()
                Button { router.dismissPresentedSheet() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                TextField("Reason (optional)", text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                Text("A new voucher with flipped debit/credit lines will be created in the same financial year when it is open, or in the latest open financial year when the original year is locked. The original is not deleted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.dismissPresentedSheet() }
                    .keyboardShortcut(.cancelAction)
                Button("Reverse") { run() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 260)
    }

    private func run() {
        guard let ctx = env.companyContext else { return }
        do {
            let hasItemEvidence = !(try VoucherItemLineRepository(db: ctx.database).findForVoucher(voucherId)).isEmpty
            if hasItemEvidence {
                _ = try ItemInvoiceService(db: ctx.database, companyId: ctx.companyId)
                    .reverse(voucherId, reason: reason.isEmpty ? nil : reason)
            } else {
                _ = try VoucherService(db: ctx.database, companyId: ctx.companyId)
                    .reverse(voucherId, reason: reason.isEmpty ? nil : reason)
            }
            env.markAccountTreeDirty()
            env.notifyDataChanged()
            env.showSuccess("Voucher reversed.")
            router.dismissPresentedSheet()
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
