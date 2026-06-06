import Foundation

public struct CrawlAppManifest: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var id: CrawlAppID
    public var displayName: String
    public var description: String
    public var availability: CrawlAppManifest.Availability
    public var binary: CrawlAppManifest.Binary
    public var execution: CrawlAppManifest.Execution?
    public var branding: CrawlAppManifest.Branding
    public var paths: CrawlAppManifest.Paths
    public var commands: [String: [String]]
    public var capabilities: [CrawlAppCapability]
    public var statusRequiresSecrets: Bool?
    public var privacy: CrawlAppManifest.Privacy
    public var configOptions: [CrawlAppManifest.ConfigOption]
    public var configSections: [CrawlAppManifest.ConfigSection]
    public var install: CrawlAppManifest.Install?

    public init(
        schemaVersion: Int = 1,
        id: CrawlAppID,
        displayName: String,
        description: String,
        availability: CrawlAppManifest.Availability = .available,
        binary: CrawlAppManifest.Binary,
        execution: CrawlAppManifest.Execution? = nil,
        branding: CrawlAppManifest.Branding,
        paths: CrawlAppManifest.Paths,
        commands: [String: [String]],
        capabilities: [CrawlAppCapability],
        statusRequiresSecrets: Bool? = nil,
        privacy: CrawlAppManifest.Privacy = CrawlAppManifest.Privacy(),
        configOptions: [CrawlAppManifest.ConfigOption] = [],
        configSections: [CrawlAppManifest.ConfigSection] = [],
        install: CrawlAppManifest.Install? = nil)
    {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.description = description
        self.availability = availability
        self.binary = binary
        self.execution = execution
        self.branding = branding
        self.paths = paths
        self.commands = commands
        self.capabilities = capabilities
        self.statusRequiresSecrets = statusRequiresSecrets
        self.privacy = privacy
        self.configOptions = configOptions
        self.configSections = configSections
        self.install = install
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case displayName = "display_name"
        case description
        case availability
        case binary
        case execution
        case branding
        case paths
        case commands
        case capabilities
        case statusRequiresSecrets = "status_requires_secrets"
        case privacy
        case configOptions = "config_options"
        case configSections = "config_sections"
        case install
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = Self.decodeSchemaVersion(from: container)
        self.id = try container.decode(CrawlAppID.self, forKey: .id)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.description = try container.decode(String.self, forKey: .description)
        self.availability = try container.decodeIfPresent(CrawlAppManifest.Availability.self, forKey: .availability) ?? .available
        self.binary = try container.decode(CrawlAppManifest.Binary.self, forKey: .binary)
        self.execution = try container.decodeIfPresent(CrawlAppManifest.Execution.self, forKey: .execution)
        self.branding = try container.decode(CrawlAppManifest.Branding.self, forKey: .branding)
        self.paths = try container.decode(CrawlAppManifest.Paths.self, forKey: .paths)
        self.commands = try Self.decodeCommands(from: container, binaryName: self.binary.name)
        self.capabilities = Self.decodeCapabilities(from: container, commands: self.commands)
        self.statusRequiresSecrets = try container.decodeIfPresent(Bool.self, forKey: .statusRequiresSecrets)
        self.privacy = try container.decodeIfPresent(CrawlAppManifest.Privacy.self, forKey: .privacy) ?? CrawlAppManifest.Privacy()
        self.configOptions = try container.decodeIfPresent([CrawlAppManifest.ConfigOption].self, forKey: .configOptions) ?? []
        self.configSections = try container.decodeIfPresent([CrawlAppManifest.ConfigSection].self, forKey: .configSections) ?? []
        self.install = try container.decodeIfPresent(CrawlAppManifest.Install.self, forKey: .install)
    }

    public var needsSecretsForStatus: Bool {
        if let statusRequiresSecrets {
            return statusRequiresSecrets
        }
        return self.commands["status"] != nil && self.configOptions.contains { option in
            option.kind == .secret && option.envVar?.nilIfBlank != nil
        }
    }

    public func executionKind(configValues: [String: String]) -> CrawlAppManifest.ExecutionKind {
        guard let execution else { return .local }
        guard let modeOptionID = execution.kindConfigID?.nilIfBlank else {
            return execution.kind
        }
        let configuredMode = configValues[modeOptionID]?.nilIfBlank
            ?? self.configOptions.first { $0.id == modeOptionID }?.defaultValue?.nilIfBlank
        guard let configuredMode else { return execution.kind }
        switch configuredMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "local":
            return .local
        case "remote", "ssh":
            return .ssh
        default:
            return execution.kind
        }
    }

    private struct CommandEnvelope: Decodable {
        var argv: [String]
    }

    private static func decodeSchemaVersion(from container: KeyedDecodingContainer<CodingKeys>) -> Int {
        if let int = try? container.decode(Int.self, forKey: .schemaVersion) {
            return int
        }
        guard let string = try? container.decode(String.self, forKey: .schemaVersion) else {
            return 1
        }
        return Int(string) ?? 1
    }

    private static func decodeCommands(
        from container: KeyedDecodingContainer<CodingKeys>,
        binaryName: String)
        throws -> [String: [String]]
    {
        if let commands = try? container.decode([String: [String]].self, forKey: .commands) {
            return Self.normalizedCommands(commands)
        }

        let envelopes = try container.decode([String: CommandEnvelope].self, forKey: .commands)
        let commands = envelopes.reduce(into: [String: [String]]()) { result, entry in
            let arguments = entry.value.argv.first == binaryName
                ? Array(entry.value.argv.dropFirst())
                : entry.value.argv
            result[entry.key] = Self.normalizedCommandArguments(arguments, action: entry.key)
        }
        return Self.normalizedCommands(commands)
    }

    private static func normalizedCommandArguments(_ arguments: [String], action: String) -> [String] {
        guard (action == "sql" || action == "query"),
              let last = arguments.last?.nilIfBlank,
              Self.isSampleSQL(last)
        else {
            return arguments
        }
        return Array(arguments.dropLast())
    }

    private static func isSampleSQL(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.hasPrefix("select ") || lowercased.hasPrefix("with ")
    }

    private static func normalizedCommands(_ commands: [String: [String]]) -> [String: [String]] {
        var normalized = commands
        if normalized["refresh"] == nil, let sync = normalized["sync"] {
            normalized["refresh"] = sync
        }
        if normalized["desktop-cache-import"] == nil {
            for alias in Self.desktopCacheCommandAliases where alias != "desktop-cache-import" {
                if let command = normalized[alias] {
                    normalized["desktop-cache-import"] = command
                    break
                }
            }
        }
        return normalized
    }

    private static func decodeCapabilities(
        from container: KeyedDecodingContainer<CodingKeys>,
        commands: [String: [String]])
        -> [CrawlAppCapability]
    {
        var capabilities: [CrawlAppCapability] = []
        if let typed = try? container.decode([CrawlAppCapability].self, forKey: .capabilities) {
            capabilities.append(contentsOf: typed)
        } else if let rawValues = try? container.decode([String].self, forKey: .capabilities) {
            capabilities.append(contentsOf: rawValues.flatMap(Self.capabilities(from:)))
        }

        for command in commands.keys.sorted() {
            capabilities.append(contentsOf: Self.capabilities(from: command))
        }

        var seen = Set<CrawlAppCapability>()
        return capabilities.filter { seen.insert($0).inserted }
    }

    private static func capabilities(from rawValue: String) -> [CrawlAppCapability] {
        switch rawValue {
        case "status":
            return [.status]
        case "doctor":
            return [.doctor]
        case "refresh", "sync":
            return [.refresh]
        case "query", "search", "sql":
            return [.search]
        case "publish":
            return [.publish]
        case "subscribe":
            return [.subscribe]
        case "update":
            return [.update]
        case let value where Self.desktopCacheCommandAliases.contains(value):
            return [.desktopCache]
        case "markdown", "export", "export-md":
            return [.exportMarkdown]
        case "table-export", "export-db", "databases":
            return [.exportDatabase]
        case "maintain":
            return [.maintain]
        case "git-share":
            return [.publish, .subscribe, .update]
        case "remote", "remote-status", "remote-archives", "remote_archive":
            return [.remoteArchive]
        case "cloud", "cloud-publish", "cloud_publish":
            return [.cloudPublish]
        default:
            return []
        }
    }

    private static let desktopCacheCommandAliases = [
        "desktop-cache-import",
        "desktop-cache",
        "desktop_cache",
        "desktopcache",
        "cache-import",
        "tap",
    ]
}
