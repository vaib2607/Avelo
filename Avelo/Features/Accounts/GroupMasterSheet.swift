import SwiftUI

/// Tally "Groups" master: Create/Alter for account groups, with a parent
/// picker over the full hierarchy (unlike ledgers, which can only sit under
/// a leaf group, a group's parent may be any other group).
public struct GroupMasterSheet: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @State private var code: String = ""
    @State private var name: String = ""
    @State private var nature: AccountNature = .assets
    @State private var parentId: AccountGroup.ID?
    @State private var groups: [AccountGroup] = []
    @State private var canSave: Bool = false
    @State private var errorMessage: String?
    @State private var existingGroup: AccountGroup?
    private let existingId: AccountGroup.ID?

    public init(existing: AccountGroup.ID? = nil) {
        self.existingId = existing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(existingId == nil ? "New Group" : "Alter Group").font(.title2.bold())
                Spacer()
                Button { router.presentedSheet = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            Form {
                TextField("Code *", text: $code)
                    .disabled(existingGroup != nil) // codes are immutable once created
                TextField("Name *", text: $name)
                Picker("Nature *", selection: $nature) {
                    ForEach(AccountNature.allCases) { n in
                        Text(n.displayName).tag(n)
                    }
                }
                Picker("Under (Primary if none)", selection: $parentId) {
                    Text("Primary").tag(AccountGroup.ID?.none)
                    ForEach(selectableParents) { g in
                        Text("\(g.code) — \(g.name)").tag(Optional(g.id))
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            .formStyle(.grouped)
            .onChange(of: code) { _, _ in refresh() }
            .onChange(of: name) { _, _ in refresh() }
            .onChange(of: nature) { _, _ in refresh() }
            .onChange(of: parentId) { _, _ in refresh() }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { router.presentedSheet = nil }
                    .keyboardShortcut(.cancelAction)
                // Not gated on `canSave` — see NewVoucherSheet.bottomBar for
                // why a validation-disabled button must still respond;
                // `attemptSave()` re-checks and leaves `errorMessage` visible.
                Button("Save") { attemptSave() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 360)
        .task { load() }
    }

    /// Excludes the group being edited and its descendants, so a group can
    /// never become its own ancestor.
    private var selectableParents: [AccountGroup] {
        guard let existingId else { return groups }
        var excluded: Set<AccountGroup.ID> = [existingId]
        var frontier = [existingId]
        while !frontier.isEmpty {
            let children = groups.filter { g in g.parentGroupId.map(frontier.contains) ?? false }
            frontier = children.map(\.id)
            excluded.formUnion(frontier)
        }
        return groups.filter { !excluded.contains($0.id) }
    }

    private func load() {
        guard let ctx = env.companyContext else { return }
        do {
            let service = AccountService(db: ctx.database, companyId: ctx.companyId)
            groups = try service.listGroups()
            if let existingId, let group = try service.findGroup(existingId) {
                existingGroup = group
                code = group.code
                name = group.name
                nature = group.nature
                parentId = group.parentGroupId
            }
        } catch {
            env.showError(AppError.wrap(error))
        }
        refresh()
    }

    private func refresh() {
        errorMessage = nil
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty, !trimmedName.isEmpty else {
            canSave = false
            return
        }
        let duplicate = groups.contains { $0.code.caseInsensitiveCompare(trimmedCode) == .orderedSame && $0.id != existingId }
        if duplicate {
            errorMessage = "A group with this code already exists."
            canSave = false
            return
        }
        canSave = true
    }

    /// Always responds to ⌘Return: saves if valid, otherwise re-checks and
    /// leaves the inline error message visible (set by `refresh()`).
    private func attemptSave() {
        refresh()
        guard canSave else { return }
        save()
    }

    private func save() {
        guard let ctx = env.companyContext else { return }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let service = AccountService(db: ctx.database, companyId: ctx.companyId)
            if var updated = existingGroup {
                updated.name = trimmedName
                updated.nature = nature
                updated.parentGroupId = parentId
                try service.updateGroup(updated)
                env.showSuccess("Group updated.")
            } else {
                _ = try service.createGroup(code: trimmedCode, name: trimmedName, nature: nature, parentGroupId: parentId)
                env.showSuccess("Group created.")
            }
            env.markAccountTreeDirty()
            env.notifyDataChanged()
            router.presentedSheet = nil
        } catch {
            env.showError(AppError.wrap(error))
        }
    }
}
