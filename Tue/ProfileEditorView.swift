import SwiftUI

struct ProfileEditorView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let profile: HostProfile?

    @State private var name: String

    init(profile: HostProfile? = nil) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(profile == nil ? "New Profile" : "Rename Profile")
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
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
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
