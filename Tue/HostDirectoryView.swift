import SwiftUI
import UniformTypeIdentifiers

struct HostDirectoryView: View {
    @Environment(HostStore.self) private var store

    @State private var selectedGroupID: UUID?
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
                            Label("Edit Host Groups", systemImage: "tag")
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
        let hosts = store.hosts(in: profile.id, groupID: selectedGroupID, query: query)

        VStack(spacing: 0) {
            HostGroupFilterBar(groups: groups, selection: $selectedGroupID)
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
                            query.isEmpty ? "No hosts in this group" : "No matching hosts",
                            systemImage: "server.rack"
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(hosts) { host in
                            NavigationLink(value: host.id) {
                                HostRowView(host: host, group: store.group(for: host, in: profile.id))
                            }
                        }
                        .onDelete { offsets in
                            pendingDeleteHostIDs = offsets.map { hosts[$0].id }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .searchable(text: $query, prompt: "Search hostname, IP, username, group, or notes")
        .onChange(of: profile.id) { _, _ in
            selectedGroupID = nil
        }
        .onChange(of: groups) { _, nextGroups in
            if let selectedGroupID, !nextGroups.contains(where: { $0.id == selectedGroupID }) {
                self.selectedGroupID = nil
            }
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
            selectedGroupID = nil
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
}

private struct ProfileTransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct HostGroupFilterBar: View {
    let groups: [HostGroup]
    @Binding var selection: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HostGroupFilterButton(
                    title: "All",
                    systemImage: "tray.full",
                    tint: .secondary,
                    isSelected: selection == nil
                ) {
                    selection = nil
                }

                ForEach(groups) { group in
                    HostGroupFilterButton(
                        title: group.name,
                        systemImage: group.symbolName,
                        tint: group.tint.color,
                        isSelected: selection == group.id
                    ) {
                        selection = group.id
                    }
                }
            }
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
                            count: profile.hosts.filter { $0.groupID == group.id }.count
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
    let group: HostGroup

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: group.symbolName)
                .foregroundStyle(group.tint.color)
                .frame(width: 28, height: 28)
                .background(group.tint.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(host.hostname)
                        .font(.headline)
                        .lineLimit(1)

                    Text(group.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(group.tint.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(group.tint.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }

                Text(host.loginSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HostDirectoryView()
        .environment(HostStore(storageURL: nil))
}
