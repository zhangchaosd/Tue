import SwiftUI
import UIKit

struct HostDetailView: View {
    @Environment(HostStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let hostID: UUID

    @State private var sheet: HostSheet?
    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if let host = store.host(id: hostID) {
                let profileID = store.profileID(containing: host.id)
                let groups = profileID.map { store.groups(for: host, in: $0) } ?? [HostGroup.fallback]
                let sameNamedHosts = profileID.map { store.hosts(namedLike: host, in: $0) } ?? []

                List {
                    Section {
                        DetailFieldRow(title: "Hostname", value: host.hostname, systemImage: "server.rack")
                        DetailFieldRow(title: "IP", value: host.ipAddress, systemImage: "network")

                        if !host.port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            DetailFieldRow(title: "Port", value: host.port, systemImage: "number")
                        }
                    }

                    Section("Accounts") {
                        ForEach(Array(host.accounts.enumerated()), id: \.element.id) { index, account in
                            AccountDetailRow(
                                account: account,
                                title: host.accounts.count > 1 ? "Account \(index + 1)" : nil
                            )
                        }
                    }

                    Section("Labels") {
                        ForEach(groups) { group in
                            Label(group.name, systemImage: group.symbolName)
                                .foregroundStyle(group.tint.color)
                        }
                    }

                    if let profileID, sameNamedHosts.count > 1 {
                        Section("Same-Name Hosts") {
                            ForEach(sameNamedHosts) { sameNamedHost in
                                let sameNamedGroups = store.groups(for: sameNamedHost, in: profileID)

                                if sameNamedHost.id == host.id {
                                    SameNamedHostRow(host: sameNamedHost, groups: sameNamedGroups, isCurrent: true)
                                } else {
                                    NavigationLink(value: sameNamedHost.id) {
                                        SameNamedHostRow(host: sameNamedHost, groups: sameNamedGroups, isCurrent: false)
                                    }
                                }
                            }
                        }
                    }

                    if !host.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section("Notes") {
                            Text(host.note)
                                .textSelection(.enabled)
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete Host", systemImage: "trash")
                        }
                    }
                }
                .navigationTitle(host.hostname)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            sheet = .editHost(hostID: host.id)
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Edit Host")
                    }
                }
                .alert("Delete Host", isPresented: $isConfirmingDelete) {
                    Button("Delete", role: .destructive) {
                        store.deleteHost(id: host.id)
                        dismiss()
                    }

                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Delete \"\(host.hostname)\"?")
                }
            } else {
                ContentUnavailableView("Host Not Found", systemImage: "questionmark.folder")
            }
        }
        .hostSheets(sheet: $sheet)
    }
}

private struct SameNamedHostRow: View {
    let host: HostRecord
    let groups: [HostGroup]
    let isCurrent: Bool

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
                HStack(spacing: 8) {
                    Text(groups.map(\.name).joined(separator: ", "))
                        .font(.headline)
                        .lineLimit(1)

                    if isCurrent {
                        Text("Current")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
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

private struct AccountDetailRow: View {
    let account: HostAccount
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Label(title, systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            DetailFieldRow(title: "Username", value: account.username, systemImage: "person")

            if !account.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DetailFieldRow(title: "Password", value: account.password, systemImage: "key")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DetailFieldRow: View {
    let title: String
    let value: String
    let systemImage: String

    @State private var didCopy = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            didCopy = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                didCopy = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }

                Spacer()

                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(didCopy ? .green : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let store = HostStore(storageURL: nil)
    let hostID = store.profiles[0].hosts[0].id
    return NavigationStack {
        HostDetailView(hostID: hostID)
            .environment(store)
    }
}
