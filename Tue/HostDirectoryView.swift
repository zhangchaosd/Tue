import SwiftUI
import UniformTypeIdentifiers

struct HostDirectoryView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.editMode) private var editMode

    @State private var selectedLabelIDs: Set<UUID> = []
    @State private var query = ""
    @State private var sheet: HostSheet?
    @State private var isExportingProfile = false
    @State private var isImportingProfile = false
    @State private var exportDocument = ProfileJSONDocument()
    @State private var transferAlert: ProfileTransferAlert?
    @State private var pendingDeleteHostIDs: [UUID] = []

    var body: some View {
        NavigationStack {
            Group {
                if let profile = store.currentProfile {
                    directoryContent(for: profile)
                } else {
                    ContentUnavailableView("No Profiles", systemImage: "person.crop.square")
                }
            }
            .navigationTitle("Host Directory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    profileMenu
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selectedLabelIDs.count == 1 && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EditButton()
                    }

                    Menu {
                        Button {
                            if let profileID = store.currentProfile?.id {
                                sheet = .renameProfile(profileID: profileID)
                            }
                        } label: {
                            Label("Rename Profile", systemImage: "pencil")
                        }

                        Button {
                            if let profileID = store.currentProfile?.id {
                                sheet = .editGroups(profileID: profileID)
                            }
                        } label: {
                            Label("Edit Labels", systemImage: "tag")
                        }

                        Button(action: exportCurrentProfile) {
                            Label("Export Profile", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                    .disabled(store.currentProfile == nil)

                    Button {
                        if let profileID = store.currentProfile?.id {
                            sheet = .addHost(profileID: profileID)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Host")
                    .disabled(store.currentProfile == nil)
                }
            }
            .navigationDestination(for: UUID.self) { hostID in
                HostDetailView(hostID: hostID)
            }
        }
        .hostSheets(sheet: $sheet)
        .fileExporter(
            isPresented: $isExportingProfile,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportDefaultFilename,
            onCompletion: handleExportResult
        )
        .fileImporter(
            isPresented: $isImportingProfile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImportResult
        )
        .alert(item: $transferAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Delete Host", isPresented: isConfirmingHostDelete) {
            Button("Delete", role: .destructive) {
                deletePendingHosts()
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteHostIDs = []
            }
        } message: {
            Text(hostDeleteMessage)
        }
    }

    @ViewBuilder
    private func directoryContent(for profile: HostProfile) -> some View {
        let groups = store.groups(in: profile.id)
        let hosts = store.hosts(in: profile.id, matchingLabelIDs: selectedLabelIDs, query: query)
        let selectedLabelID = selectedLabelIDs.first
        let canMoveHosts = selectedLabelIDs.count == 1 && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(spacing: 0) {
            HostLabelFilterBar(groups: groups, selection: $selectedLabelIDs)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            List {
                Section {
                    ProfileSummaryRow(profile: profile, groups: groups)
                }

                if hosts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            emptyTitle(selectedLabelCount: selectedLabelIDs.count),
                            systemImage: "server.rack"
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(hosts) { host in
                            NavigationLink(value: host.id) {
                                HostRowView(host: host, groups: store.groups(for: host, in: profile.id))
                            }
                        }
                        .onDelete { offsets in
                            pendingDeleteHostIDs = offsets.map { hosts[$0].id }
                        }
                        .onMove { source, destination in
                            guard canMoveHosts, let selectedLabelID else { return }
                            store.moveHosts(in: profile.id, groupID: selectedLabelID, hosts: hosts, from: source, to: destination)
                        }
                        .moveDisabled(!canMoveHosts)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .searchable(text: $query, prompt: "Search hostname, IP, username, label, or notes")
        .onChange(of: profile.id) { _, _ in
            selectedLabelIDs = []
            editMode?.wrappedValue = .inactive
        }
        .onChange(of: groups) { _, nextGroups in
            let validLabelIDs = Set(nextGroups.map(\.id))
            let nextSelection = selectedLabelIDs.intersection(validLabelIDs)
            if nextSelection != selectedLabelIDs {
                selectedLabelIDs = nextSelection
                editMode?.wrappedValue = .inactive
            }
        }
        .onChange(of: selectedLabelIDs) { _, _ in
            editMode?.wrappedValue = .inactive
        }
        .onChange(of: query) { _, _ in
            editMode?.wrappedValue = .inactive
        }
    }

    private var profileMenu: some View {
        Menu {
            ForEach(store.profiles) { profile in
                Button {
                    store.selectProfile(profile.id)
                } label: {
                    Label(
                        profile.name,
                        systemImage: profile.id == store.currentProfile?.id ? "checkmark.circle.fill" : "person.crop.square"
                    )
                }
            }

            Divider()

            Button {
                sheet = .addProfile
            } label: {
                Label("New Profile", systemImage: "plus")
            }

            Button {
                isImportingProfile = true
            } label: {
                Label("Import Profile", systemImage: "square.and.arrow.down")
            }
        } label: {
            Label(store.currentProfile?.name ?? "Profile", systemImage: "person.crop.square")
                .labelStyle(.titleAndIcon)
        }
    }

    private var exportDefaultFilename: String {
        guard let profile = store.currentProfile else { return "profile.json" }
        return "\(safeFilename(profile.name))-profile.json"
    }

    private var isConfirmingHostDelete: Binding<Bool> {
        Binding {
            !pendingDeleteHostIDs.isEmpty
        } set: { isPresented in
            if !isPresented {
                pendingDeleteHostIDs = []
            }
        }
    }

    private var hostDeleteMessage: String {
        let hostnames = pendingDeleteHostIDs.compactMap { store.host(id: $0)?.hostname }
        if pendingDeleteHostIDs.count == 1, let hostname = hostnames.first {
            return "Delete \"\(hostname)\"?"
        }
        return "Delete \(pendingDeleteHostIDs.count) selected hosts?"
    }

    private func deletePendingHosts() {
        let hostIDs = pendingDeleteHostIDs
        pendingDeleteHostIDs = []
        hostIDs.forEach { store.deleteHost(id: $0) }
    }

    private func exportCurrentProfile() {
        guard let profile = store.currentProfile else { return }

        do {
            exportDocument = try ProfileJSONDocument(profile: profile)
            isExportingProfile = true
        } catch {
            transferAlert = ProfileTransferAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            transferAlert = ProfileTransferAlert(title: "Profile Exported", message: "The JSON file was saved to the selected location.")
        case .failure(let error):
            guard !isUserCancellation(error) else { return }
            transferAlert = ProfileTransferAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importProfile(from: url)
        case .failure(let error):
            guard !isUserCancellation(error) else { return }
            transferAlert = ProfileTransferAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func importProfile(from url: URL) {
        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let profile = try store.importProfile(from: data)
            selectedLabelIDs = []
            query = ""
            transferAlert = ProfileTransferAlert(
                title: "Profile Imported",
                message: "\"\(profile.name)\" was added with \(hostCountText(profile.hosts.count))."
            )
        } catch {
            transferAlert = ProfileTransferAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func safeFilename(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = trimmedName
            .components(separatedBy: invalidCharacters)
            .filter { !$0.isEmpty }
        return components.joined(separator: "-").isEmpty ? "profile" : components.joined(separator: "-")
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.Code.userCancelled.rawValue
    }

    private func hostCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "host" : "hosts")"
    }

    private func emptyTitle(selectedLabelCount: Int) -> String {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No matching hosts"
        }

        switch selectedLabelCount {
        case 0:
            return "No hosts yet"
        case 1:
            return "No hosts with this label"
        default:
            return "No hosts with these labels"
        }
    }
}

private struct ProfileTransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct HostLabelFilterBar: View {
    let groups: [HostGroup]
    @Binding var selection: Set<UUID>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !selection.isEmpty {
                    Button {
                        selection = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear label filters")
                }

                ForEach(groups) { group in
                    HostGroupFilterButton(
                        title: group.name,
                        systemImage: group.symbolName,
                        tint: group.tint.color,
                        isSelected: selection.contains(group.id)
                    ) {
                        toggle(group.id)
                    }
                }
            }
        }
    }

    private func toggle(_ groupID: UUID) {
        if selection.contains(groupID) {
            selection.remove(groupID)
        } else {
            selection.insert(groupID)
        }
    }
}

private struct HostGroupFilterButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? .white : tint)
                .background(isSelected ? tint : tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileSummaryRow: View {
    let profile: HostProfile
    let groups: [HostGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(profile.name, systemImage: "folder")
                    .font(.headline)

                Spacer()

                Text(hostCountText(profile.hosts.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups) { group in
                        HostGroupCountPill(
                            group: group,
                            count: profile.hosts.filter { $0.groupIDs.contains(group.id) }.count
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func hostCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "host" : "hosts")"
    }
}

private struct HostGroupCountPill: View {
    let group: HostGroup
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: group.symbolName)
                .imageScale(.small)

            Text("\(count)")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(group.tint.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(group.tint.color.opacity(0.12), in: Capsule())
    }
}

private struct HostRowView: View {
    let host: HostRecord
    let groups: [HostGroup]

    private var primaryGroup: HostGroup {
        groups.first ?? HostGroup.fallback
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: primaryGroup.symbolName)
                .foregroundStyle(primaryGroup.tint.color)
                .frame(width: 28, height: 28)
                .background(primaryGroup.tint.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                Text(host.hostname)
                    .font(.headline)
                    .lineLimit(1)

                Text(host.loginSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                LabelChipRow(groups: groups)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LabelChipRow: View {
    let groups: [HostGroup]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(groups.prefix(3)) { group in
                Text(group.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(group.tint.color)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(group.tint.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }

            if groups.count > 3 {
                Text("+\(groups.count - 3)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

#Preview {
    HostDirectoryView()
        .environment(HostStore(storageURL: nil))
}
