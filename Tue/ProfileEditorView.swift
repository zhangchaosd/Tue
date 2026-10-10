import SwiftUI

struct ProfileEditorView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let profile: HostProfile?

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(profile: HostProfile? = nil) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        guard canSave else { return }
                        save()
                        dismiss()
                    }
            } header: {
                Text("Profile")
            } footer: {
                Text("Each Profile keeps its own hosts and labels, such as Work or Home.")
            }
        }
        .navigationTitle(profile == nil ? Text("New Profile") : Text("Rename Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        if let profile {
            store.updateProfileName(id: profile.id, name: name)
        } else {
            store.addProfile(name: name)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileEditorView()
            .environment(HostStore(storageURL: nil))
    }
}
