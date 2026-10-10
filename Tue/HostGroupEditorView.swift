import SwiftUI

struct HostGroupEditorView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID

    @State private var newGroupName = ""
    @State private var pendingDeleteGroup: HostGroup?
    @FocusState private var focusedGroupID: UUID?
    @FocusState private var isNewGroupNameFocused: Bool

    var body: some View {
        Group {
            if let profile = store.profile(id: profileID) {
                Form {
                    Section {
                        ForEach(store.groups(in: profileID)) { group in
                            HostGroupEditorRow(
                                profileID: profileID,
                                group: group,
                                focusedGroupID: $focusedGroupID,
                                canDelete: profile.groups.count > 1
                            ) {
                                pendingDeleteGroup = group
                            }
                        }
                    } header: {
                        Text(verbatim: profile.name)
                    } footer: {
                        Text("Tap the icon to change its symbol and color. Labels belong to the current Profile.")
                    }

                    Section("Add Label") {
                        HStack {
                            TextField("New Label Name", text: $newGroupName)
                                .focused($isNewGroupNameFocused)
                                .onSubmit(addGroup)
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
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                isNewGroupNameFocused = true
                            }
                        )
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
        .alert(Text(deleteTitle), isPresented: isConfirmingDelete) {
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
            Text(verbatim: deleteMessage)
        }
    }

    private var deleteTitle: String {
        guard let pendingDeleteGroup else { return String(localized: "Delete Label") }
        return String(localized: "Delete “\(pendingDeleteGroup.displayName)”?")
    }

    private var deleteMessage: String {
        guard let pendingDeleteGroup else { return "" }

        let count = store.hostCount(inGroup: pendingDeleteGroup.id, profileID: profileID)
        if count > 0 {
            return String(localized: "\(count) hosts will lose this label. Hosts left without labels move to the fallback label.")
        }
        return String(localized: "No hosts use this label.")
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
        isNewGroupNameFocused = true
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct HostGroupEditorRow: View {
    let profileID: UUID
    let group: HostGroup
    let focusedGroupID: FocusState<UUID?>.Binding
    let canDelete: Bool
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                LabelIconMenu(profileID: profileID, group: group)
            } label: {
                Image(systemName: group.symbolName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(group.tint.color)
                    .frame(width: 34, height: 34)
                    .background(group.tint.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Change icon for \(group.displayName)"))

            HostGroupNameField(profileID: profileID, group: group, focusedGroupID: focusedGroupID)

            Button(role: .destructive, action: delete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(canDelete ? AnyShapeStyle(.red) : AnyShapeStyle(.quaternary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Delete \(group.displayName)"))
            .disabled(!canDelete)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedGroupID.wrappedValue = group.id
            }
        )
    }
}

private struct HostGroupNameField: View {
    @Environment(HostStore.self) private var store

    let profileID: UUID
    let group: HostGroup
    let focusedGroupID: FocusState<UUID?>.Binding

    @State private var name: String

    init(profileID: UUID, group: HostGroup, focusedGroupID: FocusState<UUID?>.Binding) {
        self.profileID = profileID
        self.group = group
        self.focusedGroupID = focusedGroupID
        _name = State(initialValue: group.displayName)
    }

    var body: some View {
        TextField("Label Name", text: $name)
            .focused(focusedGroupID, equals: group.id)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(save)
            .onDisappear(perform: save)
            .onChange(of: group.displayName) { _, nextName in
                if name != nextName {
                    name = nextName
                }
            }
    }

    private func save() {
        // Leave built-in labels untouched unless the name really changed, so they keep following the system language.
        guard name.trimmingCharacters(in: .whitespacesAndNewlines) != group.displayName else { return }
        store.updateGroupName(id: group.id, name: name, in: profileID)
    }
}

private struct LabelIconMenu: View {
    @Environment(HostStore.self) private var store

    let profileID: UUID
    let group: HostGroup

    var body: some View {
        Picker(selection: tintBinding) {
            ForEach(HostGroupTint.allCases) { tint in
                Label {
                    Text(verbatim: tint.displayName)
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(tint.color)
                }
                .tag(tint)
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
        .pickerStyle(.menu)

        Picker(selection: symbolBinding) {
            ForEach(HostGroup.availableSymbols, id: \.self) { symbolName in
                Label {
                    Text(verbatim: HostGroup.displayName(forSymbol: symbolName))
                } icon: {
                    Image(systemName: symbolName)
                }
                .tag(symbolName)
            }
        } label: {
            Label("Icon", systemImage: group.symbolName)
        }
        .pickerStyle(.inline)
    }

    private var tintBinding: Binding<HostGroupTint> {
        Binding {
            group.tint
        } set: { tint in
            store.updateGroupTint(id: group.id, tint: tint, in: profileID)
        }
    }

    private var symbolBinding: Binding<String> {
        Binding {
            group.symbolName
        } set: { symbolName in
            store.updateGroupSymbol(id: group.id, symbolName: symbolName, in: profileID)
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
