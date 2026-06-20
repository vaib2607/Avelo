import SwiftUI

@MainActor
extension ReportsBody {
    @ViewBuilder
    var gstSummarySection: some View {
        if let g = vm.gstSummary {
            VStack(alignment: .leading, spacing: 6) {
                row("Output taxable", g.outputTaxablePaise)
                row("Output tax", g.outputTaxPaise)
                row("Input taxable", g.inputTaxablePaise)
                row("Input tax", g.inputTaxPaise)
                row("IGST", g.igstPaise)
                row("CGST", g.cgstPaise)
                row("SGST", g.sgstPaise)
                row("Net payable", g.netPayablePaise, bold: true)
            }
        } else {
            EmptyStateView(
                title: "No GST summary yet",
                message: "GST summary needs taxable sales or purchase activity in the selected date range.",
                systemImage: "doc.text.magnifyingglass",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

    @ViewBuilder
    var gstFilingSection: some View {
        if let g = vm.gstSummary {
            VStack(alignment: .leading, spacing: 6) {
                Text("GST Filing Views").font(.headline)
                Text("Offline filing prep only; use the summary totals below to cross-check return figures.")
                    .foregroundStyle(.secondary)
                if let filingPeriod = gstFilingPeriod {
                    Text("Period: \(filingPeriod)").font(.callout)
                }
                Divider()
                row("Output taxable", g.outputTaxablePaise)
                row("Output tax", g.outputTaxPaise)
                row("Input taxable", g.inputTaxablePaise)
                row("Input tax", g.inputTaxPaise)
                Divider()
                row("IGST", g.igstPaise)
                row("CGST", g.cgstPaise)
                row("SGST", g.sgstPaise)
                row("Net payable", g.netPayablePaise, bold: true)
            }
        } else {
            EmptyStateView(
                title: "No GST filing view yet",
                message: "The filing view mirrors the GST summary for the chosen period, so it appears when GST activity exists.",
                systemImage: "doc.text.magnifyingglass",
                actionTitle: "Refresh",
                action: { vm.reload() }
            )
        }
    }

    var gstFilingPeriod: String? {
        guard env.companyContext != nil else { return nil }
        return "\(DateFormatters.gstReturn.string(from: vm.fromDate)) - \(DateFormatters.gstReturn.string(from: vm.toDate))"
    }

    @ViewBuilder
    func row(_ title: String, _ paise: Int64, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Currency.formatPaise(paise)).monospacedDigit()
        }
        .font(bold ? .body.bold() : .body)
    }

}
