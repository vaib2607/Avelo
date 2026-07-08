import SwiftUI
import Observation

public struct GSTView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: GSTViewModel?

    public init() {}

    public var body: some View {
        GSTContent(vm: vm)
            .navigationTitle("GST")
            .toolbar {
                ToolbarItem {
                    Button("Refresh") { vm?.reload() }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
            .task(id: reloadKey) { setup() }
    }

    private var reloadKey: String {
        let company = env.companyContext?.companyId.uuidString ?? "none"
        return "\(company)-\(env.dataRevision)"
    }

    private func setup() {
        guard let ctx = env.companyContext else {
            vm = nil
            return
        }
        if vm == nil || vm?.companyId != ctx.companyId {
            let model = GSTViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            vm = model
        }
    }
}

@MainActor
private struct GSTContent: View {
    let vm: GSTViewModel?

    var body: some View {
        if let vm {
            GSTBody(vm: vm)
        } else {
            ProgressView()
        }
    }
}

@MainActor
private struct GSTBody: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var vm: GSTViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleChrome(
                title: "GST",
                subtitle: "Offline tax summary, filing-ready views, and return exports in one focused workspace.",
                hints: [
                    .init(title: "GST", key: "⌘6"),
                    .init(title: "Refresh", key: "⌘R"),
                    .init(title: "Export CSV", key: "⇧⌘E")
                ],
                primaryActionTitle: "Refresh",
                primaryActionSystemImage: "arrow.clockwise",
                primaryAction: { vm.reload() }
            )
            HStack {
                DatePicker("From", selection: $vm.fromDate, displayedComponents: .date)
                    .onChange(of: vm.fromDate) { _, _ in vm.reload() }
                DatePicker("To", selection: $vm.toDate, displayedComponents: .date)
                    .onChange(of: vm.toDate) { _, _ in vm.reload() }
                Spacer()
                Button("Export CSV") { exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("GST Summary") {
                        if let s = vm.summary {
                            VStack(alignment: .leading, spacing: 6) {
                                gstRow("Outward taxable", s.outputTaxablePaise)
                                gstRow("Outward tax", s.outputTaxPaise)
                                gstRow("Inward taxable", s.inputTaxablePaise)
                                gstRow("Inward tax", s.inputTaxPaise)
                                Divider()
                                gstRow("IGST", s.igstPaise)
                                gstRow("CGST", s.cgstPaise)
                                gstRow("SGST", s.sgstPaise)
                                gstRow("Net payable", s.netPayablePaise)
                            }
                        } else {
                            Text("No GST activity in the selected period.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    GroupBox("Filing View") {
                        if let filing = vm.filing {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Period: \(filing.period)")
                                Text("Summary-only filing prep is available offline.")
                                    .foregroundStyle(.secondary)
                                gstRow("IGST", filing.igstPaise)
                                gstRow("CGST", filing.cgstPaise)
                                gstRow("SGST", filing.sgstPaise)
                            }
                        } else {
                            Text("No filing view available.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ModuleFooterBar(items: [
                        .init(title: "Next", detail: "Use Summary for totals, then Export CSV for filing prep."),
                        .init(title: "Shortcut", detail: "⌘R refreshes, ⇧⌘E exports a CSV."),
                        .init(title: "Scope", detail: "This stays local and offline; no remote filing.")
                    ])
                }
                .padding(16)
            }
        }
    }

    private func exportCSV() {
        Task {
            do {
                let data = try vm.summaryCSVData()
                let name = "GST-Summary-\(DateFormatters.isoDate.string(from: vm.fromDate))-to-\(DateFormatters.isoDate.string(from: vm.toDate)).csv"
                if let url = try await NSPanelBridge.saveData(data, suggestedName: name) {
                    env.showSuccess("GST summary exported to \(url.lastPathComponent).")
                }
            } catch {
                env.showError(AppError.wrap(error))
            }
        }
    }

    @ViewBuilder
    private func gstRow(_ title: String, _ paise: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Currency.formatPaise(paise)).monospacedDigit()
        }
    }
}

@MainActor
@Observable
public final class GSTViewModel {
    public var fromDate: Date = Date()
    public var toDate: Date = Date()
    public var summary: ReportResult.GstSummary?
    public var filing: GSTService.GSTReturn?
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase

    public init(companyId: Company.ID, db: SQLiteDatabase) {
        self.companyId = companyId
        self.db = db
    }

    public func reload() {
        do {
            let svc = GSTService(db: db, companyId: companyId)
            summary = try svc.summary(fromDate: fromDate, toDate: toDate)
            filing = try svc.buildReturn(fromDate: fromDate, toDate: toDate)
        } catch {
            self.error = AppError.wrap(error)
        }
    }

    /// Builds the GST summary CSV bytes for the current period. The view layer
    /// owns the save panel and writes the returned data to disk.
    public func summaryCSVData() throws -> Data {
        let svc = GSTService(db: db, companyId: companyId)
        return try svc.exportGSTSummaryCSV(fromDate: fromDate, toDate: toDate)
    }
}
