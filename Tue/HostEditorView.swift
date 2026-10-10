import SwiftUI

struct HostEditorView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID
    let host: HostRecord?

    @State private var hostname: String
    @State private var domainName: String
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
        _domainName = State(initialValue: host?.domainName ?? "")
        _ipAddress = State(initialValue: host?.ipAddress ?? "")
        _port = State(initialValue: host?.port ?? "22")
        _groupIDs = State(initialValue: Set(host?.groupIDs ?? [HostGroup.developmentID]))
        _accounts = State(initialValue: initialAccounts)
        _note = State(initialValue: host?.note ?? "")
    }

    var body: some View {
        let groups = store.groups(in: profileID)

        Form {
            Section {
                TextField("Hostname", text: $hostname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Domain (Optional)", text: $domainName)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("IP Address", text: $ipAddress)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                LabeledContent("Port") {
                    TextField("22", text: $port)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: port) { _, nextPort in
                            let digits = String(nextPort.filter { $0.isASCII && $0.isNumber }.prefix(5))
                            if digits != nextPort {
                                port = digits
                            }
                        }
                }
            } header: {
                Text("Basic Info")
            } footer: {
                if !missingFields.isEmpty {
                    Text("Required: \(missingFields.formatted(.list(type: .and)))")
                }
            }

            Section {
                LabelSelectionRows(groups: groups, selection: $groupIDs)
            } header: {
                Text("Labels")
            } footer: {
                Text("A host can have several labels.")
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
                    withAnimation {
                        accounts.append(HostAccount(username: "", password: ""))
                    }
                } label: {
                    Label("Add Account", systemImage: "plus.circle.fill")
                }
            }

            Section("Notes") {
                TextField("Add a note", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(host == nil ? Text("Add Host") : Text("Edit Host"))
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
        missingFields.isEmpty && !groupIDs.isEmpty
    }

    private var missingFields: [String] {
        var fields: [String] = []
        if trimmed(hostname).isEmpty {
            fields.append(String(localized: "Hostname"))
        }
        if trimmed(ipAddress).isEmpty {
            fields.append(String(localized: "IP Address"))
        }
        if !accounts.contains(where: { !trimmed($0.username).isEmpty }) {
            fields.append(String(localized: "Username"))
        }
        return fields
    }

    private func saveHost() {
        let nextHost = HostRecord(
            id: host?.id ?? UUID(),
            hostname: trimmed(hostname),
            domainName: trimmed(domainName),
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
        withAnimation {
            accounts.removeAll { $0.id == id }
        }
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
                    Label {
                        Text(verbatim: group.displayName)
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: group.symbolName)
                            .foregroundStyle(group.tint.color)
                    }

                    Spacer()

                    Image(systemName: selection.contains(group.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(group.id) ? AnyShapeStyle(group.tint.color) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(group.id) ? .isSelected : [])
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func toggle(_ groupID: UUID) {
        if selection.contains(groupID) {
            // Keep at least one label selected.
            if selection.count > 1 {
                selection.remove(groupID)
            }
        } else {
            selection.insert(groupID)
        }
    }
}

private struct HostAccountEditorRow: View {
    @Binding var account: HostAccount

    let showsDelete: Bool
    let delete: () -> Void

    @State private var isPasswordVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                TextField("Username", text: $account.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if showsDelete {
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete Account")
                }
            }

            Divider()

            HStack {
                Image(systemName: "key")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Group {
                    if isPasswordVisible {
                        TextField("Password (Optional)", text: $account.password)
                    } else {
                        SecureField("Password (Optional)", text: $account.password)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isPasswordVisible ? Text("Hide Password") : Text("Show Password"))
            }
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
