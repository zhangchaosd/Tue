import SwiftUI

struct HostEditorView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID
    let host: HostRecord?

    @State private var hostname: String
    @State private var ipAddress: String
    @State private var port: String
    @State private var groupIDs: Set<UUID>
    @State private var accounts: [HostAccount]
    @State private var note: String

    init(profileID: UUID, host: HostRecord?) {
        self.profileID = profileID
        self.host = host
        let initialAccounts: [HostAccount]
        if let accounts = host?.accounts, !accounts.isEmpty {
            initialAccounts = accounts
        } else {
            initialAccounts = [HostAccount(username: "", password: "")]
        }
        _hostname = State(initialValue: host?.hostname ?? "")
        _ipAddress = State(initialValue: host?.ipAddress ?? "")
        _port = State(initialValue: host?.port ?? "22")
        _groupIDs = State(initialValue: Set(host?.groupIDs ?? [HostGroup.developmentID]))
        _accounts = State(initialValue: initialAccounts)
        _note = State(initialValue: host?.note ?? "")
    }

    var body: some View {
        let groups = store.groups(in: profileID)

        Form {
            Section("Basic Info") {
                TextField("Hostname", text: $hostname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("IP Address", text: $ipAddress)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Labels") {
                LabelSelectionRows(groups: groups, selection: $groupIDs)
            }

            Section("Login Info") {
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
            }

            Section("Accounts") {
                ForEach($accounts) { $account in
                    HostAccountEditorRow(
                        account: $account,
                        showsDelete: account.id != accounts.first?.id
                    ) {
                        deleteAccount(id: account.id)
                    }
                }

                Button {
                    accounts.append(HostAccount(username: "", password: ""))
                } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
            }

            Section("Notes") {
                TextField("Notes", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(host == nil ? "Add Host" : "Edit Host")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectFallbackGroupsIfNeeded(groups)
            ensureAccountRow()
        }
        .onChange(of: groups) { _, nextGroups in
            selectFallbackGroupsIfNeeded(nextGroups)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveHost()
                }
                .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        !trimmed(hostname).isEmpty
            && !trimmed(ipAddress).isEmpty
            && !groupIDs.isEmpty
            && accounts.contains { !trimmed($0.username).isEmpty }
    }

    private func saveHost() {
        let nextHost = HostRecord(
            id: host?.id ?? UUID(),
            hostname: trimmed(hostname),
            ipAddress: trimmed(ipAddress),
            port: trimmed(port),
            groupIDs: orderedGroupIDs(),
            accounts: accounts,
            note: trimmed(note)
        )
        store.upsertHost(nextHost, in: profileID)
        dismiss()
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectFallbackGroupsIfNeeded(_ groups: [HostGroup]) {
        let validGroupIDs = Set(groups.map(\.id))
        groupIDs = groupIDs.intersection(validGroupIDs)
        if groupIDs.isEmpty, let fallbackGroupID = groups.first?.id {
            groupIDs = [fallbackGroupID]
        }
    }

    private func orderedGroupIDs() -> [UUID] {
        store.groups(in: profileID)
            .map(\.id)
            .filter { groupIDs.contains($0) }
    }

    private func deleteAccount(id: UUID) {
        guard accounts.count > 1 else { return }
        accounts.removeAll { $0.id == id }
        ensureAccountRow()
    }

    private func ensureAccountRow() {
        if accounts.isEmpty {
            accounts = [HostAccount(username: "", password: "")]
        }
    }
}

private struct LabelSelectionRows: View {
    let groups: [HostGroup]
    @Binding var selection: Set<UUID>

    var body: some View {
        ForEach(groups) { group in
            Button {
                toggle(group.id)
            } label: {
                HStack {
                    Label(group.name, systemImage: group.symbolName)
                        .foregroundStyle(group.tint.color)

                    Spacer()

                    if selection.contains(group.id) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func toggle(_ groupID: UUID) {
        if selection.contains(groupID), selection.count > 1 {
            selection.remove(groupID)
        } else {
            selection.insert(groupID)
        }
    }
}

private struct HostAccountEditorRow: View {
    @Binding var account: HostAccount

    let showsDelete: Bool
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Username", text: $account.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if showsDelete {
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete Account")
                }
            }

            TextField("Password", text: $account.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let store = HostStore(storageURL: nil)
    let profileID = store.profiles[0].id
    return NavigationStack {
        HostEditorView(profileID: profileID, host: nil)
            .environment(store)
    }
}
