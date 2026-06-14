import SwiftUI

struct HostGroupEditorView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID

    @State private var newGroupName = ""
    @State private var pendingDeleteGroup: HostGroup?

    var body: some View {
        Group {
            if let profile = store.profile(id: profileID) {
                Form {
                    Section(profile.name) {
                        ForEach(store.groups(in: profileID)) { group in
                            HostGroupEditorRow(
                                profileID: profileID,
                                group: group,
                                canDelete: profile.groups.count > 1
                            ) {
                                pendingDeleteGroup = group
                            }
                        }
                    }

                    Section("Add Label") {
                        HStack {
                            TextField("Name", text: $newGroupName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Button {
                                addGroup()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .imageScale(.large)
                            }
                            .accessibilityLabel("Add Label")
                            .disabled(trimmed(newGroupName).isEmpty)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Profile Not Found", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("Edit Labels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Delete Label", isPresented: isConfirmingDelete) {
            if let pendingDeleteGroup {
                Button("Delete", role: .destructive) {
                    store.deleteGroup(id: pendingDeleteGroup.id, in: profileID)
                    self.pendingDeleteGroup = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteGroup = nil
            }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        guard let pendingDeleteGroup else { return "" }

        let count = store.hostCount(inGroup: pendingDeleteGroup.id, profileID: profileID)
        if count > 0 {
            return "\(hostCountText(count)) using \"\(pendingDeleteGroup.name)\" will lose this label. Hosts with no labels will move to the fallback label."
        }
        return pendingDeleteGroup.name
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding {
            pendingDeleteGroup != nil
        } set: { isPresented in
            if !isPresented {
                pendingDeleteGroup = nil
            }
        }
    }

    private func addGroup() {
        guard store.addGroup(name: newGroupName, in: profileID) != nil else { return }
        newGroupName = ""
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hostCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "host" : "hosts")"
    }
}

private struct HostGroupEditorRow: View {
    let profileID: UUID
    let group: HostGroup
    let canDelete: Bool
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: group.symbolName)
                .foregroundStyle(group.tint.color)
                .frame(width: 24)
                .contextMenu {
                    LabelIconMenu(profileID: profileID, group: group)
                }

            Menu {
                LabelIconMenu(profileID: profileID, group: group)
            } label: {
                Image(systemName: "chevron.down.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Change icon for \(group.name)")

            HostGroupNameField(profileID: profileID, group: group)

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(group.name)")
            .disabled(!canDelete)
        }
    }
}

private struct HostGroupNameField: View {
    @Environment(HostStore.self) private var store

    let profileID: UUID
    let group: HostGroup

    @State private var name: String

    init(profileID: UUID, group: HostGroup) {
        self.profileID = profileID
        self.group = group
        _name = State(initialValue: group.name)
    }

    var body: some View {
        TextField("Label Name", text: $name)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(save)
            .onDisappear(perform: save)
            .onChange(of: group.name) { _, nextName in
                if name != nextName {
                    name = nextName
                }
            }
    }

    private func save() {
        store.updateGroupName(id: group.id, name: name, in: profileID)
    }
}

private struct LabelIconMenu: View {
    @Environment(HostStore.self) private var store

    let profileID: UUID
    let group: HostGroup

    var body: some View {
        ForEach(HostGroup.availableSymbols, id: \.self) { symbolName in
            Button {
                store.updateGroupSymbol(id: group.id, symbolName: symbolName, in: profileID)
            } label: {
                Label(symbolName, systemImage: symbolName)
            }
        }
    }
}

#Preview {
    let store = HostStore(storageURL: nil)
    let profileID = store.profiles[0].id
    return NavigationStack {
        HostGroupEditorView(profileID: profileID)
            .environment(store)
    }
}
