import SwiftUI
import UIKit
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
    @State private var copiedValue: String?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let profile = store.currentProfile {
                    directoryContent(for: profile)
                } else {
                    ContentUnavailableView("No Profiles", systemImage: "person.crop.square")
                }
            }
            .navigationTitle("Hosts")
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
                        Image(systemName: "ellipsis")
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
                title: Text(verbatim: alert.title),
                message: Text(verbatim: alert.message),
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
            Text(verbatim: hostDeleteMessage)
        }
        .sensoryFeedback(.success, trigger: copiedValue) { _, newValue in newValue != nil }
        #if DEBUG
        .task {
            applyScreenshotScene()
        }
        #endif
    }

    #if DEBUG
    private func applyScreenshotScene() {
        guard let scene = ScreenshotScene.current, let profile = store.currentProfile else { return }
        let firstHost = profile.hosts.first
        switch scene {
        case .list:
            break
        case .detail:
            if let firstHost {
                path = [firstHost.id]
            }
        case .filter:
            selectedLabelIDs = [HostGroup.testingID]
        case .search:
            query = "prod"
        case .editor:
            if let firstHost {
                sheet = .editHost(hostID: firstHost.id)
            }
        case .labels:
            sheet = .editGroups(profileID: profile.id)
        }
    }
    #endif

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
                        emptyState(profileID: profile.id)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(hosts) { host in
                            NavigationLink(value: host.id) {
                                HostRowView(host: host, groups: store.groups(for: host, in: profile.id))
                            }
                            .contextMenu {
                                hostContextMenu(for: host)
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
        .searchable(text: $query, prompt: Text("Search hosts"))
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
                    Label {
                        Text(verbatim: profile.name)
                    } icon: {
                        Image(systemName: profile.id == store.currentProfile?.id ? "checkmark.circle.fill" : "person.crop.square")
                    }
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
            HStack(spacing: 4) {
                Text(verbatim: store.currentProfile?.name ?? String(localized: "Profile"))
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
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
            return String(localized: "Delete “\(hostname)”? This can’t be undone.")
        }
        return String(localized: "Delete \(pendingDeleteHostIDs.count) selected hosts? This can’t be undone.")
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
            transferAlert = ProfileTransferAlert(title: String(localized: "Export Failed"), message: error.localizedDescription)
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            transferAlert = ProfileTransferAlert(
                title: String(localized: "Profile Exported"),
                message: String(localized: "The JSON file was saved to the selected location.")
            )
        case .failure(let error):
            guard !isUserCancellation(error) else { return }
            transferAlert = ProfileTransferAlert(title: String(localized: "Export Failed"), message: error.localizedDescription)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importProfile(from: url)
        case .failure(let error):
            guard !isUserCancellation(error) else { return }
            transferAlert = ProfileTransferAlert(title: String(localized: "Import Failed"), message: error.localizedDescription)
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
                title: String(localized: "Profile Imported"),
                message: String(localized: "“\(profile.name)” was added with \(profile.hosts.count) hosts.")
            )
        } catch {
            transferAlert = ProfileTransferAlert(title: String(localized: "Import Failed"), message: error.localizedDescription)
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

    @ViewBuilder
    private func emptyState(profileID: UUID) -> some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: query)
        } else if !selectedLabelIDs.isEmpty {
            ContentUnavailableView {
                Label {
                    selectedLabelIDs.count == 1 ? Text("No Hosts with This Label") : Text("No Hosts with These Labels")
                } icon: {
                    Image(systemName: "tag.slash")
                }
            } description: {
                Text("Hosts that have every selected label appear here.")
            } actions: {
                Button("Clear Filters") {
                    selectedLabelIDs = []
                }
            }
        } else {
            ContentUnavailableView {
                Label("No Hosts Yet", systemImage: "server.rack")
            } description: {
                Text("Save a hostname, IP, port, and login once, then copy them with a tap.")
            } actions: {
                Button("Add Host") {
                    sheet = .addHost(profileID: profileID)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func hostContextMenu(for host: HostRecord) -> some View {
        Section {
            Button {
                copy(host.ipAddress)
            } label: {
                Label("Copy IP", systemImage: "network")
            }

            if !host.domainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    copy(host.domainName)
                } label: {
                    Label("Copy Domain", systemImage: "globe")
                }
            }

            if let account = host.accounts.first {
                Button {
                    copy(account.username)
                } label: {
                    Label("Copy Username", systemImage: "person")
                }

                Button {
                    copy(host.sshCommand(for: account))
                } label: {
                    Label("Copy SSH Command", systemImage: "terminal")
                }
            }
        }

        Section {
            Button {
                sheet = .editHost(hostID: host.id)
            } label: {
                Label("Edit Host", systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingDeleteHostIDs = [host.id]
            } label: {
                Label("Delete Host", systemImage: "trash")
            }
        }
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        copiedValue = nil
        copiedValue = value
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
                        title: group.displayName,
                        systemImage: group.symbolName,
                        tint: group.tint.color,
                        isSelected: selection.contains(group.id)
                    ) {
                        toggle(group.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func toggle(_ groupID: UUID) {
        withAnimation(.snappy(duration: 0.25)) {
            if selection.contains(groupID) {
                selection.remove(groupID)
            } else {
                selection.insert(groupID)
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
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : tint)
            .background(isSelected ? tint : tint.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ProfileSummaryRow: View {
    let profile: HostProfile
    let groups: [HostGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(verbatim: profile.name)
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                }
                .font(.headline)

                Spacer()

                Text("\(profile.hosts.count) hosts")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(group.displayName): \(count) hosts"))
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
                .font(.body.weight(.medium))
                .foregroundStyle(primaryGroup.tint.color)
                .frame(width: 36, height: 36)
                .background(primaryGroup.tint.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: host.hostname)
                    .font(.headline)
                    .lineLimit(1)

                Text(verbatim: host.loginSummary)
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
                Text(verbatim: group.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(group.tint.color)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(group.tint.color.opacity(0.12), in: Capsule())
            }

            if groups.count > 3 {
                Text(verbatim: "+\(groups.count - 3)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}

#Preview {
    HostDirectoryView()
        .environment(HostStore(storageURL: nil))
}
