import Foundation
import SwiftUI

enum HostGroupTint: String, CaseIterable, Codable, Identifiable {
    case teal
    case indigo
    case orange
    case red
    case gray
    case blue
    case green
    case purple
    case pink
    case mint

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .teal:
            .teal
        case .indigo:
            .indigo
        case .orange:
            .orange
        case .red:
            .red
        case .gray:
            .secondary
        case .blue:
            .blue
        case .green:
            .green
        case .purple:
            .purple
        case .pink:
            .pink
        case .mint:
            .mint
        }
    }

    var displayName: String {
        switch self {
        case .teal: String(localized: "Teal")
        case .indigo: String(localized: "Indigo")
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Red")
        case .gray: String(localized: "Gray")
        case .blue: String(localized: "Blue")
        case .green: String(localized: "Green")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .mint: String(localized: "Mint")
        }
    }

    static let customPalette: [HostGroupTint] = [.blue, .green, .purple, .pink, .mint, .teal, .indigo]
}

struct HostGroup: Identifiable, Codable, Hashable {
    static let developmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let testingID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let stagingID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    static let productionID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    static let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000199")!

    var id: UUID
    var name: String
    var symbolName: String
    var tint: HostGroupTint
    var sortOrder: Int

    static let availableSymbols = [
        "tag",
        "folder",
        "tray",
        "hammer",
        "checklist",
        "shippingbox",
        "server.rack",
        "terminal",
        "network",
        "globe",
        "lock",
        "key",
        "externaldrive",
        "cloud",
        "desktopcomputer",
        "laptopcomputer",
        "bolt",
        "shield",
        "wrench.and.screwdriver"
    ]

    /// Built-in labels are stored with their English names so exported JSON stays stable;
    /// they are shown in the system language as long as the user hasn't renamed them.
    var displayName: String {
        guard let builtIn = Self.builtInNames[id], name == builtIn.english else { return name }
        return String(localized: builtIn.localized)
    }

    private static let builtInNames: [UUID: (english: String, localized: String.LocalizationValue)] = [
        developmentID: ("Development", "Development"),
        testingID: ("Testing", "Testing"),
        stagingID: ("Staging", "Staging"),
        productionID: ("Production", "Production"),
        otherID: ("Other", "Other")
    ]

    static func displayName(forSymbol symbolName: String) -> String {
        switch symbolName {
        case "tag": String(localized: "Tag")
        case "folder": String(localized: "Folder")
        case "tray": String(localized: "Tray")
        case "hammer": String(localized: "Hammer")
        case "checklist": String(localized: "Checklist")
        case "shippingbox": String(localized: "Box")
        case "server.rack": String(localized: "Server")
        case "terminal": String(localized: "Terminal")
        case "network": String(localized: "Network")
        case "globe": String(localized: "Globe")
        case "lock": String(localized: "Lock")
        case "key": String(localized: "Key")
        case "externaldrive": String(localized: "Drive")
        case "cloud": String(localized: "Cloud")
        case "desktopcomputer": String(localized: "Desktop")
        case "laptopcomputer": String(localized: "Laptop")
        case "bolt": String(localized: "Bolt")
        case "shield": String(localized: "Shield")
        case "wrench.and.screwdriver": String(localized: "Tools")
        default: symbolName
        }
    }

    static var defaultGroups: [HostGroup] {
        [
            HostGroup(id: developmentID, name: "Development", symbolName: "hammer", tint: .teal, sortOrder: 0),
            HostGroup(id: testingID, name: "Testing", symbolName: "checklist", tint: .indigo, sortOrder: 1),
            HostGroup(id: stagingID, name: "Staging", symbolName: "shippingbox", tint: .orange, sortOrder: 2),
            HostGroup(id: productionID, name: "Production", symbolName: "server.rack", tint: .red, sortOrder: 3),
            HostGroup(id: otherID, name: "Other", symbolName: "tray", tint: .gray, sortOrder: 4)
        ]
    }

    static var fallback: HostGroup {
        HostGroup(id: otherID, name: "Other", symbolName: "tray", tint: .gray, sortOrder: 0)
    }

    static func custom(name: String, sortOrder: Int) -> HostGroup {
        let tint = HostGroupTint.customPalette[sortOrder % HostGroupTint.customPalette.count]
        return HostGroup(id: UUID(), name: name, symbolName: "tag", tint: tint, sortOrder: sortOrder)
    }
}

private enum LegacyHostEnvironment: Codable {
    case development
    case testing
    case staging
    case production
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue.lowercased() {
        case "development", "\u{5F00}\u{53D1}":
            self = .development
        case "testing", "\u{6D4B}\u{8BD5}":
            self = .testing
        case "staging", "\u{9884}\u{53D1}":
            self = .staging
        case "production", "\u{751F}\u{4EA7}":
            self = .production
        default:
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .development:
            try container.encode("development")
        case .testing:
            try container.encode("testing")
        case .staging:
            try container.encode("staging")
        case .production:
            try container.encode("production")
        case .other:
            try container.encode("other")
        }
    }

    var groupID: UUID {
        switch self {
        case .development:
            HostGroup.developmentID
        case .testing:
            HostGroup.testingID
        case .staging:
            HostGroup.stagingID
        case .production:
            HostGroup.productionID
        case .other:
            HostGroup.otherID
        }
    }
}

struct HostProfile: Identifiable, Hashable {
    var id: UUID
    var name: String
    var groups: [HostGroup]
    var hosts: [HostRecord]
    var hostOrderByGroupID: [String: [UUID]] = [:]
}

extension HostProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case groups
        case hosts
        case hostOrderByGroupID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        var decodedGroups = try container.decodeIfPresent([HostGroup].self, forKey: .groups) ?? HostGroup.defaultGroups
        if decodedGroups.isEmpty {
            decodedGroups = [HostGroup.fallback]
        }

        let groupIDs = Set(decodedGroups.map(\.id))
        let fallbackGroupID = decodedGroups.first { $0.id == HostGroup.otherID }?.id ?? decodedGroups[0].id
        groups = decodedGroups
        hostOrderByGroupID = try container.decodeIfPresent([String: [UUID]].self, forKey: .hostOrderByGroupID) ?? [:]
        hosts = try container.decode([HostRecord].self, forKey: .hosts).map { host in
            var normalizedHost = host
            normalizedHost.groupIDs = normalizedHost.groupIDs.filter { groupIDs.contains($0) }.uniqued()
            if normalizedHost.groupIDs.isEmpty {
                normalizedHost.groupIDs = [fallbackGroupID]
            }
            return normalizedHost
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(groups, forKey: .groups)
        try container.encode(hosts, forKey: .hosts)
        try container.encode(hostOrderByGroupID, forKey: .hostOrderByGroupID)
    }
}

struct HostAccount: Identifiable, Hashable {
    var id: UUID
    var username: String
    var password: String

    init(id: UUID = UUID(), username: String, password: String) {
        self.id = id
        self.username = username
        self.password = password
    }
}

extension HostAccount: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case password
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
    }
}

struct HostRecord: Identifiable, Hashable {
    var id: UUID
    var hostname: String
    var domainName: String
    var ipAddress: String
    var port: String
    var groupIDs: [UUID]
    var accounts: [HostAccount]
    var note: String

    init(
        id: UUID = UUID(),
        hostname: String,
        domainName: String = "",
        ipAddress: String,
        port: String,
        groupID: UUID,
        accounts: [HostAccount],
        note: String
    ) {
        self.init(
            id: id,
            hostname: hostname,
            domainName: domainName,
            ipAddress: ipAddress,
            port: port,
            groupIDs: [groupID],
            accounts: accounts,
            note: note
        )
    }

    init(
        id: UUID = UUID(),
        hostname: String,
        domainName: String = "",
        ipAddress: String,
        port: String,
        groupIDs: [UUID],
        accounts: [HostAccount],
        note: String
    ) {
        self.id = id
        self.hostname = hostname
        self.domainName = domainName
        self.ipAddress = ipAddress
        self.port = port
        self.groupIDs = groupIDs.uniqued()
        self.accounts = accounts
        self.note = note
    }

    var groupID: UUID {
        get {
            groupIDs.first ?? HostGroup.otherID
        }
        set {
            groupIDs = [newValue]
        }
    }

    /// The domain when one is set, otherwise the IP address.
    var preferredAddress: String {
        let trimmedDomainName = domainName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDomainName.isEmpty ? ipAddress : trimmedDomainName
    }

    func sshCommand(for account: HostAccount) -> String {
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let portArgument = trimmedPort.isEmpty || trimmedPort == "22" ? "" : " -p \(trimmedPort)"
        return "ssh\(portArgument) \(account.username)@\(preferredAddress)"
    }

    var loginSummary: String {
        let address = preferredAddress
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = trimmedPort.isEmpty
            ? address
            : "\(address):\(trimmedPort)"

        guard let firstAccount = accounts.first else { return endpoint }
        if accounts.count == 1 {
            return "\(firstAccount.username)@\(endpoint)"
        }
        return "\(firstAccount.username) +\(accounts.count - 1) @ \(endpoint)"
    }
}

extension HostRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case hostname
        case domainName
        case ipAddress
        case username
        case password
        case port
        case groupID
        case groupIDs
        case accounts
        case environment
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hostname = try container.decode(String.self, forKey: .hostname)
        domainName = try container.decodeIfPresent(String.self, forKey: .domainName) ?? ""
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        port = try container.decode(String.self, forKey: .port)
        note = try container.decode(String.self, forKey: .note)

        if let accounts = try container.decodeIfPresent([HostAccount].self, forKey: .accounts) {
            self.accounts = accounts
        } else {
            let username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
            let password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
            accounts = username.isEmpty ? [] : [HostAccount(username: username, password: password)]
        }

        if let groupIDs = try container.decodeIfPresent([UUID].self, forKey: .groupIDs), !groupIDs.isEmpty {
            self.groupIDs = groupIDs.uniqued()
        } else if let groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID) {
            self.groupIDs = [groupID]
        } else if let legacyEnvironment = try? container.decode(LegacyHostEnvironment.self, forKey: .environment) {
            groupIDs = [legacyEnvironment.groupID]
        } else {
            groupIDs = [HostGroup.otherID]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hostname, forKey: .hostname)
        try container.encode(domainName, forKey: .domainName)
        try container.encode(ipAddress, forKey: .ipAddress)
        try container.encode(port, forKey: .port)
        try container.encode(groupIDs, forKey: .groupIDs)
        try container.encode(groupID, forKey: .groupID)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(note, forKey: .note)
    }
}

struct HostArchive: Codable {
    var selectedProfileID: UUID?
    var profiles: [HostProfile]
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
