import SwiftUI

enum HostSheet: Identifiable, Hashable {
    case addHost(profileID: UUID)
    case editHost(hostID: UUID)
    case addProfile
    case renameProfile(profileID: UUID)
    case editGroups(profileID: UUID)

    var id: String {
        switch self {
        case .addHost(let profileID):
            "add-host-\(profileID.uuidString)"
        case .editHost(let hostID):
            "edit-host-\(hostID.uuidString)"
        case .addProfile:
            "add-profile"
        case .renameProfile(let profileID):
            "rename-profile-\(profileID.uuidString)"
        case .editGroups(let profileID):
            "edit-groups-\(profileID.uuidString)"
        }
    }
}

struct HostSheetContent: View {
    @Environment(HostStore.self) private var store

    let destination: HostSheet

    var body: some View {
        NavigationStack {
            switch destination {
            case .addHost(let profileID):
                HostEditorView(profileID: profileID, host: nil)
            case .editHost(let hostID):
                if let host = store.host(id: hostID), let profileID = store.profileID(containing: hostID) {
                    HostEditorView(profileID: profileID, host: host)
                } else {
                    ContentUnavailableView("Host Not Found", systemImage: "questionmark.folder")
                }
            case .addProfile:
                ProfileEditorView()
            case .renameProfile(let profileID):
                if let profile = store.profile(id: profileID) {
                    ProfileEditorView(profile: profile)
                } else {
                    ContentUnavailableView("Profile Not Found", systemImage: "questionmark.folder")
                }
            case .editGroups(let profileID):
                HostGroupEditorView(profileID: profileID)
            }
        }
    }
}

extension View {
    func hostSheets(sheet: Binding<HostSheet?>) -> some View {
        self.sheet(item: sheet) { destination in
            HostSheetContent(destination: destination)
        }
    }
}
