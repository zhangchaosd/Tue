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
                        HostHeaderView(host: host, groups: groups)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    Section {
                        DetailFieldRow(title: "Hostname", value: host.hostname, systemImage: "server.rack")

                        if !host.domainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            DetailFieldRow(title: "Domain", value: host.domainName, systemImage: "globe")
                        }

                        DetailFieldRow(title: "IP Address", value: host.ipAddress, systemImage: "point.3.connected.trianglepath.dotted")

                        if !host.port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            DetailFieldRow(title: "Port", value: host.port, systemImage: "number")
                        }
                    } footer: {
                        Text("Tap any field to copy it.")
                    }

                    ForEach(Array(host.accounts.enumerated()), id: \.element.id) { index, account in
                        Section {
                            DetailFieldRow(title: "Username", value: account.username, systemImage: "person")

                            if !account.password.isEmpty {
                                DetailFieldRow(title: "Password", value: account.password, systemImage: "key", isSecret: true)
                            }

                            DetailFieldRow(
                                title: "SSH Command",
                                value: host.sshCommand(for: account),
                                systemImage: "terminal",
                                isMonospaced: true
                            )
                        } header: {
                            if host.accounts.count > 1 {
                                Text("Account \(index + 1)")
                            } else {
                                Text("Account")
                            }
                        }
                    }

                    if let profileID, sameNamedHosts.count > 1 {
                        Section {
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
                        } header: {
                            Text("Same-Name Hosts")
                        } footer: {
                            Text("Other hosts in this Profile with the same hostname.")
                        }
                    }

                    if !host.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section("Notes") {
                            Text(verbatim: host.note)
                                .textSelection(.enabled)
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete Host", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle(host.hostname)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") {
                            sheet = .editHost(hostID: host.id)
                        }
                    }
                }
                .confirmationDialog(
                    Text("Delete “\(host.hostname)”?"),
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete Host", role: .destructive) {
                        dismiss()
                        store.deleteHost(id: host.id)
                    }
                } message: {
                    Text("This can’t be undone.")
                }
            } else {
                ContentUnavailableView("Host Not Found", systemImage: "questionmark.folder")
            }
        }
        .hostSheets(sheet: $sheet)
    }
}

private struct HostHeaderView: View {
    let host: HostRecord
    let groups: [HostGroup]

    private var primaryGroup: HostGroup {
        groups.first ?? HostGroup.fallback
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: primaryGroup.symbolName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(primaryGroup.tint.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 4) {
                Text(verbatim: host.hostname)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(verbatim: host.loginSummary)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                ForEach(groups) { group in
                    Label {
                        Text(verbatim: group.displayName)
                    } icon: {
                        Image(systemName: group.symbolName)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(group.tint.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(group.tint.color.opacity(0.14), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
                .frame(width: 32, height: 32)
                .background(primaryGroup.tint.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: groups.map(\.displayName).formatted(.list(type: .and, width: .narrow)))
                        .font(.headline)
                        .lineLimit(1)

                    if isCurrent {
                        Text("Current")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text(verbatim: host.loginSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DetailFieldRow: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    var isSecret = false
    var isMonospaced = false

    @State private var didCopy = false
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: copy) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.tint)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Group {
                            if isSecret && !isRevealed {
                                Text(verbatim: String(repeating: "•", count: min(max(value.count, 6), 12)))
                            } else {
                                Text(verbatim: value)
                            }
                        }
                        .font(isMonospaced || isSecret ? .body.monospaced() : .body)
                        .foregroundStyle(.primary)
                        .contentTransition(.opacity)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(didCopy ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Copies to the clipboard"))

            if isSecret {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isRevealed.toggle()
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isRevealed ? Text("Hide Password") : Text("Show Password"))
            }
        }
        .sensoryFeedback(.success, trigger: didCopy) { _, newValue in newValue }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation {
                didCopy = false
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = value
        withAnimation(.snappy(duration: 0.2)) {
            didCopy = true
        }
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
