import SwiftUI

public struct AuditView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var vm: AuditViewModel?
    @State private var selected: AuditEvent?

    public init() {}

    public var body: some View {
        AuditContent(vm: vm, selected: $selected)
            .navigationTitle("Audit Log")
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
            let model = AuditViewModel(companyId: ctx.companyId, db: ctx.database)
            model.reload()
            vm = model
        }
    }
}

@MainActor
private struct AuditContent: View {
    let vm: AuditViewModel?
    @Binding var selected: AuditEvent?

    var body: some View {
        if let vm {
            AuditBody(vm: vm, selected: $selected)
        } else { ProgressView() }
    }
}

@MainActor
private struct AuditBody: View {
    @Bindable var vm: AuditViewModel
    @Binding var selected: AuditEvent?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    SearchBar(text: $vm.query, placeholder: "Search entity id / reason…")
                    Picker("Entity", selection: $vm.entityTypeFilter) {
                        Text("All").tag("")
                        ForEach(vm.entityTypes, id: \.self) { t in Text(t).tag(t) }
                    }
                    .frame(width: 180)
                }
                .padding(12)
                .onChange(of: vm.query) { _, _ in vm.reload() }
                .onChange(of: vm.entityTypeFilter) { _, _ in vm.reload() }
                Divider()
                Table(vm.events, selection: Binding(
                    get: { selected?.id },
                    set: { newId in
                        if let newId = newId {
                            selected = vm.events.first(where: { $0.id == newId })
                        } else { selected = nil }
                    }
                )) {
                    TableColumn("Timestamp") { e in
                        Text(DateFormatters.isoTimestamp.string(from: e.timestamp))
                    }
                    TableColumn("Action", value: \.action.rawValue)
                    TableColumn("Entity", value: \.entityType)
                    TableColumn("Entity ID") { e in
                        Text(String(e.entityId.prefix(8)) + "…")
                    }
                }
            }
            .frame(minWidth: 600)
            if let s = selected {
                detail(event: s)
                    .frame(minWidth: 360)
            } else {
                Text("Select an event to view details.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func detail(event: AuditEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Action: \(event.action.rawValue)").font(.headline)
                Text("Entity: \(event.entityType) (\(event.entityId))")
                Text("At: \(DateFormatters.isoTimestamp.string(from: event.timestamp))")
                if let r = event.reason, !r.isEmpty { Text("Reason: \(r)") }
                Divider()
                Text("Before").font(.subheadline.bold())
                Text(event.snapshotBeforeJson ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Divider()
                Text("After").font(.subheadline.bold())
                Text(event.snapshotAfterJson ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(16)
        }
    }
}
