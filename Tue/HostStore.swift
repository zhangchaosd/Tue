import Foundation
import Observation

enum ProfileImportError: LocalizedError {
    case invalidProfileJSON

    var errorDescription: String? {
        switch self {
        case .invalidProfileJSON:
            "Choose a Profile JSON file exported by Tue."
        }
    }
}

@Observable
final class HostStore {
    private(set) var profiles: [HostProfile]
    var selectedProfileID: UUID?

    @ObservationIgnored private let archiveURL: URL?
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    @ObservationIgnored private let decoder = JSONDecoder()

    init(storageURL: URL? = HostStore.defaultStorageURL, seedProfiles: [HostProfile] = HostStore.sampleProfiles) {
        archiveURL = storageURL

        if let storageURL, var archive = Self.loadArchive(from: storageURL) {
            let didMigrateBuiltInText = Self.migrateBuiltInEnglishText(in: &archive)
            profiles = archive.profiles
            selectedProfileID = archive.selectedProfileID ?? archive.profiles.first?.id
            if didMigrateBuiltInText {
                save()
            }
        } else {
            profiles = seedProfiles
            selectedProfileID = profiles.first?.id
            save()
        }
    }

    var currentProfile: HostProfile? {
        guard let selectedProfileID else { return profiles.first }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    var storageURL: URL {
        archiveURL ?? Self.defaultStorageURL
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        save()
    }

    func addProfile(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let profile = HostProfile(id: UUID(), name: trimmedName, groups: HostGroup.defaultGroups, hosts: [])
        profiles.append(profile)
        selectedProfileID = profile.id
        save()
    }

    func updateProfileName(id profileID: UUID, name: String) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        profiles[profileIndex].name = trimmedName
        save()
    }

    @discardableResult
    func importProfile(from data: Data) throws -> HostProfile {
        let decodedProfile: HostProfile
        do {
            decodedProfile = try decoder.decode(HostProfile.self, from: data)
        } catch {
            throw ProfileImportError.invalidProfileJSON
        }

        let importedProfile = importedCopy(of: decodedProfile)
        profiles.append(importedProfile)
        selectedProfileID = importedProfile.id
        save()
        return importedProfile
    }

    func profile(id profileID: UUID) -> HostProfile? {
        profiles.first { $0.id == profileID }
    }

    func groups(in profileID: UUID) -> [HostGroup] {
        guard let profile = profile(id: profileID) else { return [] }
        return sortedGroups(profile.groups)
    }

    func group(id groupID: UUID, in profileID: UUID) -> HostGroup? {
        profile(id: profileID)?.groups.first { $0.id == groupID }
    }

    func group(for host: HostRecord, in profileID: UUID) -> HostGroup {
        group(id: host.groupID, in: profileID) ?? HostGroup.fallback
    }

    func groups(for host: HostRecord, in profileID: UUID) -> [HostGroup] {
        let profileGroups = groups(in: profileID)
        let groupsByID = Dictionary(uniqueKeysWithValues: profileGroups.map { ($0.id, $0) })
        let hostGroups = host.groupIDs.compactMap { groupsByID[$0] }
        return hostGroups.isEmpty ? [HostGroup.fallback] : hostGroups
    }

    func hostCount(inGroup groupID: UUID, profileID: UUID) -> Int {
        profile(id: profileID)?.hosts.filter { $0.groupIDs.contains(groupID) }.count ?? 0
    }

    @discardableResult
    func addGroup(name: String, in profileID: UUID) -> HostGroup? {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return nil }

        let trimmedName = trimmed(name)
        guard !trimmedName.isEmpty else { return nil }

        let nextSortOrder = (profiles[profileIndex].groups.map(\.sortOrder).max() ?? -1) + 1
        let group = HostGroup.custom(name: trimmedName, sortOrder: nextSortOrder)
        profiles[profileIndex].groups.append(group)
        save()
        return group
    }

    func updateGroupName(id groupID: UUID, name: String, in profileID: UUID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }),
              let groupIndex = profiles[profileIndex].groups.firstIndex(where: { $0.id == groupID })
        else {
            return
        }

        let trimmedName = trimmed(name)
        profiles[profileIndex].groups[groupIndex].name = trimmedName.isEmpty ? "Untitled Group" : trimmedName
        save()
    }

    func updateGroupSymbol(id groupID: UUID, symbolName: String, in profileID: UUID) {
        guard HostGroup.availableSymbols.contains(symbolName),
              let profileIndex = profiles.firstIndex(where: { $0.id == profileID }),
              let groupIndex = profiles[profileIndex].groups.firstIndex(where: { $0.id == groupID })
        else {
            return
        }

        profiles[profileIndex].groups[groupIndex].symbolName = symbolName
        save()
    }

    func deleteGroup(id groupID: UUID, in profileID: UUID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        guard profiles[profileIndex].groups.count > 1 else { return }

        guard let fallbackGroupID = fallbackGroupID(afterDeleting: groupID, in: profiles[profileIndex]) else { return }
        profiles[profileIndex].groups.removeAll { $0.id == groupID }

        for hostIndex in profiles[profileIndex].hosts.indices {
            profiles[profileIndex].hosts[hostIndex].groupIDs.removeAll { $0 == groupID }
            if profiles[profileIndex].hosts[hostIndex].groupIDs.isEmpty {
                profiles[profileIndex].hosts[hostIndex].groupIDs = [fallbackGroupID]
            }
        }
        profiles[profileIndex].hostOrderByGroupID[groupID.uuidString] = nil
        normalizeHostOrders(for: profileIndex)
        save()
    }

    func hosts(in profileID: UUID, matchingLabelIDs labelIDs: Set<UUID>, query: String) -> [HostRecord] {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return [] }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profile.hosts
            .filter { host in
                guard !labelIDs.isEmpty else { return true }
                return labelIDs.isSubset(of: Set(host.groupIDs))
            }
            .filter { host in
                guard !normalizedQuery.isEmpty else { return true }
                let groupNames = host.groupIDs
                    .compactMap { group(id: $0, in: profileID)?.name }
                    .joined(separator: " ")
                let accountNames = host.accounts.map(\.username).joined(separator: " ")
                return [
                    host.hostname,
                    host.ipAddress,
                    accountNames,
                    groupNames,
                    host.note
                ]
                .joined(separator: " ")
                .lowercased()
                .contains(normalizedQuery)
            }
            .sorted { left, right in
                if labelIDs.count == 1, let groupID = labelIDs.first {
                    let order = profile.hostOrderByGroupID[groupID.uuidString] ?? []
                    let orderRanks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
                    let leftRank = orderRanks[left.id] ?? Int.max
                    let rightRank = orderRanks[right.id] ?? Int.max
                    if leftRank != rightRank {
                        return leftRank < rightRank
                    }
                }

                let leftSortOrder = primarySortOrder(for: left, in: profile)
                let rightSortOrder = primarySortOrder(for: right, in: profile)

                if leftSortOrder == rightSortOrder {
                    return left.hostname.localizedStandardCompare(right.hostname) == .orderedAscending
                }
                return leftSortOrder < rightSortOrder
            }
    }

    func hosts(namedLike host: HostRecord, in profileID: UUID) -> [HostRecord] {
        guard let profile = profile(id: profileID) else { return [] }

        let normalizedHostname = trimmed(host.hostname).lowercased()
        guard !normalizedHostname.isEmpty else { return [] }

        return profile.hosts
            .filter { trimmed($0.hostname).lowercased() == normalizedHostname }
            .sorted { left, right in
                let leftSortOrder = primarySortOrder(for: left, in: profile)
                let rightSortOrder = primarySortOrder(for: right, in: profile)

                if leftSortOrder == rightSortOrder {
                    return left.ipAddress.localizedStandardCompare(right.ipAddress) == .orderedAscending
                }
                return leftSortOrder < rightSortOrder
            }
    }

    func host(id: UUID) -> HostRecord? {
        for profile in profiles {
            if let host = profile.hosts.first(where: { $0.id == id }) {
                return host
            }
        }
        return nil
    }

    func profileID(containing hostID: UUID) -> UUID? {
        profiles.first { profile in
            profile.hosts.contains { $0.id == hostID }
        }?.id
    }

    func upsertHost(_ host: HostRecord, in profileID: UUID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        guard let normalizedHost = normalized(host, in: profiles[profileIndex]) else { return }

        if let hostIndex = profiles[profileIndex].hosts.firstIndex(where: { $0.id == normalizedHost.id }) {
            profiles[profileIndex].hosts[hostIndex] = normalizedHost
        } else {
            profiles[profileIndex].hosts.append(normalizedHost)
        }
        normalizeHostOrders(for: profileIndex)
        save()
    }

    func deleteHost(id: UUID) {
        for profileIndex in profiles.indices {
            profiles[profileIndex].hosts.removeAll { $0.id == id }
            normalizeHostOrders(for: profileIndex)
        }
        save()
    }

    func moveHosts(in profileID: UUID, groupID: UUID, hosts visibleHosts: [HostRecord], from source: IndexSet, to destination: Int) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        var orderedHostIDs = visibleHosts.map(\.id)
        let movingIDs = source.sorted().map { orderedHostIDs[$0] }
        for index in source.sorted(by: >) {
            orderedHostIDs.remove(at: index)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        orderedHostIDs.insert(contentsOf: movingIDs, at: adjustedDestination)
        profiles[profileIndex].hostOrderByGroupID[groupID.uuidString] = orderedHostIDs
        normalizeHostOrders(for: profileIndex)
        save()
    }

    func save() {
        guard let archiveURL else { return }

        let archive = HostArchive(selectedProfileID: currentProfile?.id, profiles: profiles)
        do {
            try FileManager.default.createDirectory(
                at: archiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(archive)
            try data.write(to: archiveURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save host archive: \(error.localizedDescription)")
        }
    }

    private func normalized(_ host: HostRecord, in profile: HostProfile) -> HostRecord? {
        let hostname = trimmed(host.hostname)
        let ipAddress = trimmed(host.ipAddress)
        let accounts = host.accounts
            .map { account in
                HostAccount(
                    id: account.id,
                    username: trimmed(account.username),
                    password: account.password
                )
            }
            .filter { !trimmed($0.username).isEmpty }

        guard !hostname.isEmpty, !ipAddress.isEmpty, !accounts.isEmpty else { return nil }
        let validGroupIDs = host.groupIDs
            .filter { groupID in profile.groups.contains { $0.id == groupID } }
            .uniqued()
        let groupIDs = validGroupIDs.isEmpty ? [fallbackGroupID(in: profile)] : validGroupIDs

        return HostRecord(
            id: host.id,
            hostname: hostname,
            ipAddress: ipAddress,
            port: trimmed(host.port),
            groupIDs: groupIDs,
            accounts: accounts,
            note: trimmed(host.note)
        )
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sortedGroups(_ groups: [HostGroup]) -> [HostGroup] {
        groups.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private func primarySortOrder(for host: HostRecord, in profile: HostProfile) -> Int {
        host.groupIDs
            .compactMap { groupID in profile.groups.first { $0.id == groupID }?.sortOrder }
            .min() ?? Int.max
    }

    private func normalizeHostOrders(for profileIndex: Int) {
        let hosts = profiles[profileIndex].hosts
        let hostIDs = Set(hosts.map(\.id))
        let labelIDs = Set(profiles[profileIndex].groups.map(\.id))

        profiles[profileIndex].hostOrderByGroupID = profiles[profileIndex].hostOrderByGroupID.reduce(into: [:]) { result, entry in
            guard let groupID = UUID(uuidString: entry.key), labelIDs.contains(groupID) else { return }
            let orderedIDs = entry.value.filter { hostIDs.contains($0) }.uniqued()
            guard !orderedIDs.isEmpty else { return }
            result[entry.key] = orderedIDs
        }

        for groupID in labelIDs {
            let key = groupID.uuidString
            let existing = profiles[profileIndex].hostOrderByGroupID[key] ?? []
            let existingSet = Set(existing)
            let missing = hosts
                .filter { $0.groupIDs.contains(groupID) && !existingSet.contains($0.id) }
                .sorted { $0.hostname.localizedStandardCompare($1.hostname) == .orderedAscending }
                .map(\.id)
            profiles[profileIndex].hostOrderByGroupID[key] = existing + missing
        }
    }

    private func importedCopy(of profile: HostProfile) -> HostProfile {
        let groups = sortedGroups(profile.groups.isEmpty ? HostGroup.defaultGroups : profile.groups)
        let importedProfileID = UUID()
        let importedName = uniqueProfileName(basedOn: profile.name)
        let profileShell = HostProfile(id: importedProfileID, name: importedName, groups: groups, hosts: [])
        let groupIDs = Set(groups.map(\.id))
        let fallbackGroupID = fallbackGroupID(in: profileShell)
        var hostIDMap: [UUID: UUID] = [:]

        let hosts = profile.hosts.compactMap { host -> HostRecord? in
            var importedHost = host
            let originalHostID = host.id
            importedHost.id = UUID()
            hostIDMap[originalHostID] = importedHost.id
            importedHost.groupIDs = host.groupIDs.filter { groupIDs.contains($0) }.uniqued()
            if importedHost.groupIDs.isEmpty {
                importedHost.groupIDs = [fallbackGroupID]
            }
            importedHost.accounts = host.accounts.map { account in
                HostAccount(id: UUID(), username: account.username, password: account.password)
            }
            return normalized(importedHost, in: profileShell)
        }

        var importedProfile = HostProfile(id: importedProfileID, name: importedName, groups: groups, hosts: hosts)
        importedProfile.hostOrderByGroupID = profile.hostOrderByGroupID.reduce(into: [:]) { result, entry in
            let importedOrder = entry.value.compactMap { hostIDMap[$0] }
            if !importedOrder.isEmpty {
                result[entry.key] = importedOrder
            }
        }

        let importedStore = HostStore(storageURL: nil, seedProfiles: [importedProfile])
        importedStore.normalizeHostOrders(for: 0)
        return importedStore.profiles[0]
    }

    private func uniqueProfileName(basedOn name: String) -> String {
        let baseName = trimmed(name).isEmpty ? "Imported Profile" : trimmed(name)
        guard profiles.contains(where: { $0.name == baseName }) else { return baseName }

        let copyName = "\(baseName) Copy"
        guard profiles.contains(where: { $0.name == copyName }) else { return copyName }

        var index = 2
        while profiles.contains(where: { $0.name == "\(copyName) \(index)" }) {
            index += 1
        }
        return "\(copyName) \(index)"
    }

    private func fallbackGroupID(in profile: HostProfile) -> UUID {
        profile.groups.first { $0.id == HostGroup.otherID }?.id ?? profile.groups.first?.id ?? HostGroup.otherID
    }

    private func fallbackGroupID(afterDeleting deletedGroupID: UUID, in profile: HostProfile) -> UUID? {
        profile.groups.first { $0.id == HostGroup.otherID && $0.id != deletedGroupID }?.id
            ?? sortedGroups(profile.groups).first { $0.id != deletedGroupID }?.id
    }

    private static func loadArchive(from storageURL: URL) -> HostArchive? {
        do {
            let data = try Data(contentsOf: storageURL)
            let archive = try JSONDecoder().decode(HostArchive.self, from: data)
            guard !archive.profiles.isEmpty else { return nil }
            return archive
        } catch {
            return nil
        }
    }

    private static func migrateBuiltInEnglishText(in archive: inout HostArchive) -> Bool {
        var didMigrate = false
        let defaultGroupNamesByID = Dictionary(uniqueKeysWithValues: HostGroup.defaultGroups.map { ($0.id, $0.name) })

        for profileIndex in archive.profiles.indices {
            switch archive.profiles[profileIndex].name {
            case "\u{5DE5}\u{4F5C}":
                archive.profiles[profileIndex].name = "Work"
                didMigrate = true
            case "\u{5BB6}\u{5EAD}":
                archive.profiles[profileIndex].name = "Home"
                didMigrate = true
            default:
                break
            }

            for groupIndex in archive.profiles[profileIndex].groups.indices {
                let group = archive.profiles[profileIndex].groups[groupIndex]
                guard let defaultName = defaultGroupNamesByID[group.id],
                      isLegacyBuiltInGroupName(group.name, for: group.id),
                      group.name != defaultName
                else {
                    continue
                }
                archive.profiles[profileIndex].groups[groupIndex].name = defaultName
                didMigrate = true
            }

            for hostIndex in archive.profiles[profileIndex].hosts.indices {
                let note = archive.profiles[profileIndex].hosts[hostIndex].note
                if let migratedNote = migratedBuiltInNote(note), migratedNote != note {
                    archive.profiles[profileIndex].hosts[hostIndex].note = migratedNote
                    didMigrate = true
                }
            }
        }

        return didMigrate
    }

    private static func isLegacyBuiltInGroupName(_ name: String, for groupID: UUID) -> Bool {
        switch groupID {
        case HostGroup.developmentID:
            name == "\u{5F00}\u{53D1}"
        case HostGroup.testingID:
            name == "\u{6D4B}\u{8BD5}"
        case HostGroup.stagingID:
            name == "\u{9884}\u{53D1}"
        case HostGroup.productionID:
            name == "\u{751F}\u{4EA7}"
        case HostGroup.otherID:
            name == "\u{5176}\u{4ED6}"
        default:
            false
        }
    }

    private static func migratedBuiltInNote(_ note: String) -> String? {
        switch note {
        case "\u{5F00}\u{53D1}\u{63A5}\u{53E3}\u{670D}\u{52A1}\u{FF0C}\u{65E5}\u{5E38}\u{8054}\u{8C03}\u{4F7F}\u{7528}\u{3002}":
            "Development API service for daily integration testing."
        case "\u{6D4B}\u{8BD5}\u{5E93}\u{FF0C}\u{53EA}\u{4FDD}\u{7559}\u{6700}\u{8FD1}\u{4E24}\u{5468}\u{6570}\u{636E}\u{3002}":
            "Test database with only the last two weeks of data."
        case "\u{751F}\u{4EA7}\u{5165}\u{53E3}\u{4E3B}\u{673A}\u{FF0C}\u{53D8}\u{66F4}\u{524D}\u{5148}\u{786E}\u{8BA4}\u{7A97}\u{53E3}\u{3002}":
            "Production entry host. Confirm the maintenance window before making changes."
        case "\u{5BB6}\u{5EAD} NAS\u{3002}":
            "Home NAS."
        default:
            nil
        }
    }

    private static var storageDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tue", isDirectory: true)
    }

    private static var defaultStorageURL: URL {
        storageDirectoryURL.appendingPathComponent("hosts.json")
    }

    private static var sampleProfiles: [HostProfile] {
        [
            HostProfile(
                id: UUID(),
                name: "Work",
                groups: HostGroup.defaultGroups,
                hosts: [
                    HostRecord(
                        id: UUID(),
                        hostname: "dev-api-01",
                        ipAddress: "10.0.2.21",
                        port: "22",
                        groupID: HostGroup.developmentID,
                        accounts: [
                            HostAccount(username: "deploy", password: "dev-password"),
                            HostAccount(username: "readonly", password: "readonly-password")
                        ],
                        note: "Development API service for daily integration testing."
                    ),
                    HostRecord(
                        id: UUID(),
                        hostname: "test-db-01",
                        ipAddress: "10.0.8.15",
                        port: "5432",
                        groupID: HostGroup.testingID,
                        accounts: [
                            HostAccount(username: "tester", password: "test-password")
                        ],
                        note: "Test database with only the last two weeks of data."
                    ),
                    HostRecord(
                        id: UUID(),
                        hostname: "prod-web-01",
                        ipAddress: "172.16.0.12",
                        port: "22",
                        groupID: HostGroup.productionID,
                        accounts: [
                            HostAccount(username: "ops", password: "prod-password")
                        ],
                        note: "Production entry host. Confirm the maintenance window before making changes."
                    )
                ]
            ),
            HostProfile(
                id: UUID(),
                name: "Home",
                groups: HostGroup.defaultGroups,
                hosts: [
                    HostRecord(
                        id: UUID(),
                        hostname: "home-nas",
                        ipAddress: "192.168.31.20",
                        port: "22",
                        groupID: HostGroup.productionID,
                        accounts: [
                            HostAccount(username: "admin", password: "nas-password")
                        ],
                        note: "Home NAS."
                    )
                ]
            )
        ]
    }
}
