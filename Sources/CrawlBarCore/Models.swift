import Foundation

public struct CrawlAppID: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        self.rawValue
    }

    public static func < (lhs: CrawlAppID, rhs: CrawlAppID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct CrawlAppManifest: Codable, Equatable, Sendable, Identifiable {
    public enum Availability: String, Codable, Equatable, Sendable {
        case available
        case comingSoon = "coming_soon"
    }

    public struct Binary: Codable, Equatable, Sendable {
        public var name: String
        public var minVersion: String?

        public init(name: String, minVersion: String? = nil) {
            self.name = name
            self.minVersion = minVersion
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case minVersion = "min_version"
        }
    }

    public enum ExecutionKind: String, Codable, Equatable, Sendable {
        case local
        case ssh
    }

    public struct Execution: Codable, Equatable, Sendable {
        public var kind: ExecutionKind
        public var kindConfigID: String?
        public var targetConfigID: String?
        public var runAsConfigID: String?
        public var remoteEnvFileConfigID: String?
        public var remoteBinary: String?

        public init(
            kind: ExecutionKind = .local,
            kindConfigID: String? = nil,
            targetConfigID: String? = nil,
            runAsConfigID: String? = nil,
            remoteEnvFileConfigID: String? = nil,
            remoteBinary: String? = nil)
        {
            self.kind = kind
            self.kindConfigID = kindConfigID
            self.targetConfigID = targetConfigID
            self.runAsConfigID = runAsConfigID
            self.remoteEnvFileConfigID = remoteEnvFileConfigID
            self.remoteBinary = remoteBinary
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case kindConfigID = "kind_config_id"
            case targetConfigID = "target_config_id"
            case runAsConfigID = "run_as_config_id"
            case remoteEnvFileConfigID = "remote_env_file_config_id"
            case remoteBinary = "remote_binary"
        }
    }

    public struct Branding: Codable, Equatable, Sendable {
        public var symbolName: String
        public var accentColor: String
        public var iconPath: String?
        public var bundleIdentifier: String?

        public init(
            symbolName: String,
            accentColor: String,
            iconPath: String? = nil,
            bundleIdentifier: String? = nil)
        {
            self.symbolName = symbolName
            self.accentColor = accentColor
            self.iconPath = iconPath
            self.bundleIdentifier = bundleIdentifier
        }

        private enum CodingKeys: String, CodingKey {
            case symbolName = "symbol_name"
            case accentColor = "accent_color"
            case iconPath = "icon_path"
            case bundleIdentifier = "bundle_identifier"
        }
    }

    public struct Paths: Codable, Equatable, Sendable {
        public var defaultConfig: String?
        public var configEnv: String?
        public var defaultDatabase: String?
        public var defaultCache: String?
        public var defaultLogs: String?
        public var defaultShare: String?

        public init(
            defaultConfig: String? = nil,
            configEnv: String? = nil,
            defaultDatabase: String? = nil,
            defaultCache: String? = nil,
            defaultLogs: String? = nil,
            defaultShare: String? = nil)
        {
            self.defaultConfig = defaultConfig
            self.configEnv = configEnv
            self.defaultDatabase = defaultDatabase
            self.defaultCache = defaultCache
            self.defaultLogs = defaultLogs
            self.defaultShare = defaultShare
        }

        private enum CodingKeys: String, CodingKey {
            case defaultConfig = "default_config"
            case configEnv = "config_env"
            case defaultDatabase = "default_database"
            case defaultCache = "default_cache"
            case defaultLogs = "default_logs"
            case defaultShare = "default_share"
        }
    }

    public struct Privacy: Codable, Equatable, Sendable {
        public var containsPrivateMessages: Bool
        public var exportsSecrets: Bool
        public var localOnlyScopes: [String]

        public init(
            containsPrivateMessages: Bool = false,
            exportsSecrets: Bool = false,
            localOnlyScopes: [String] = [])
        {
            self.containsPrivateMessages = containsPrivateMessages
            self.exportsSecrets = exportsSecrets
            self.localOnlyScopes = localOnlyScopes
        }

        private enum CodingKeys: String, CodingKey {
            case containsPrivateMessages = "contains_private_messages"
            case exportsSecrets = "exports_secrets"
            case localOnlyScopes = "local_only_scopes"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.containsPrivateMessages = try container.decodeIfPresent(Bool.self, forKey: .containsPrivateMessages) ?? false
            self.exportsSecrets = try container.decodeIfPresent(Bool.self, forKey: .exportsSecrets) ?? false
            self.localOnlyScopes = try container.decodeIfPresent([String].self, forKey: .localOnlyScopes) ?? []
        }
    }

    public enum InstallMethod: String, Codable, Equatable, Sendable {
        case homebrew
    }

    public struct Install: Codable, Equatable, Sendable {
        public var method: InstallMethod
        public var package: String

        public init(method: InstallMethod, package: String) {
            self.method = method
            self.package = package
        }
    }

    public enum ConfigOptionKind: String, Codable, Equatable, Sendable {
        case string
        case secret
        case boolean
        case number
        case choice
    }

    public struct ConfigOption: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var kind: ConfigOptionKind
        public var help: String?
        public var placeholder: String?
        public var defaultValue: String?
        public var choices: [String]
        public var envVar: String?
        public var configKey: String?

        public init(
            id: String,
            label: String,
            kind: ConfigOptionKind = .string,
            help: String? = nil,
            placeholder: String? = nil,
            defaultValue: String? = nil,
            choices: [String] = [],
            envVar: String? = nil,
            configKey: String? = nil)
        {
            self.id = id
            self.label = label
            self.kind = kind
            self.help = help
            self.placeholder = placeholder
            self.defaultValue = defaultValue
            self.choices = choices
            self.envVar = envVar
            self.configKey = configKey
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case label
            case kind
            case help
            case placeholder
            case defaultValue = "default_value"
            case choices
            case envVar = "env_var"
            case configKey = "config_key"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? self.id
            self.kind = try container.decodeIfPresent(ConfigOptionKind.self, forKey: .kind) ?? .string
            self.help = try container.decodeIfPresent(String.self, forKey: .help)
            self.placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
            self.defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            self.choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
            self.envVar = try container.decodeIfPresent(String.self, forKey: .envVar)
            self.configKey = try container.decodeIfPresent(String.self, forKey: .configKey)
        }
    }

    public struct ConfigSection: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var caption: String?
        public var optionIDs: [String]

        public init(id: String, title: String, caption: String? = nil, optionIDs: [String]) {
            self.id = id
            self.title = title
            self.caption = caption
            self.optionIDs = optionIDs
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case caption
            case optionIDs = "option_ids"
        }
    }

    public var schemaVersion: Int
    public var id: CrawlAppID
    public var displayName: String
    public var description: String
    public var availability: Availability
    public var binary: Binary
    public var execution: Execution?
    public var branding: Branding
    public var paths: Paths
    public var commands: [String: [String]]
    public var capabilities: [CrawlAppCapability]
    public var statusRequiresSecrets: Bool?
    public var privacy: Privacy
    public var configOptions: [ConfigOption]
    public var configSections: [ConfigSection]
    public var install: Install?

    public init(
        schemaVersion: Int = 1,
        id: CrawlAppID,
        displayName: String,
        description: String,
        availability: Availability = .available,
        binary: Binary,
        execution: Execution? = nil,
        branding: Branding,
        paths: Paths,
        commands: [String: [String]],
        capabilities: [CrawlAppCapability],
        statusRequiresSecrets: Bool? = nil,
        privacy: Privacy = Privacy(),
        configOptions: [ConfigOption] = [],
        configSections: [ConfigSection] = [],
        install: Install? = nil)
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
        self.availability = try container.decodeIfPresent(Availability.self, forKey: .availability) ?? .available
        self.binary = try container.decode(Binary.self, forKey: .binary)
        self.execution = try container.decodeIfPresent(Execution.self, forKey: .execution)
        self.branding = try container.decode(Branding.self, forKey: .branding)
        self.paths = try container.decode(Paths.self, forKey: .paths)
        self.commands = try Self.decodeCommands(from: container, binaryName: self.binary.name)
        self.capabilities = Self.decodeCapabilities(from: container, commands: self.commands)
        self.statusRequiresSecrets = try container.decodeIfPresent(Bool.self, forKey: .statusRequiresSecrets)
        self.privacy = try container.decodeIfPresent(Privacy.self, forKey: .privacy) ?? Privacy()
        self.configOptions = try container.decodeIfPresent([ConfigOption].self, forKey: .configOptions) ?? []
        self.configSections = try container.decodeIfPresent([ConfigSection].self, forKey: .configSections) ?? []
        self.install = try container.decodeIfPresent(Install.self, forKey: .install)
    }

    public var needsSecretsForStatus: Bool {
        if let statusRequiresSecrets {
            return statusRequiresSecrets
        }
        return self.commands["status"] != nil && self.configOptions.contains { option in
            option.kind == .secret && option.envVar?.nilIfBlank != nil
        }
    }

    public func executionKind(configValues: [String: String]) -> ExecutionKind {
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

public enum CrawlAppCapability: String, Codable, Equatable, Sendable, CaseIterable {
    case status
    case doctor
    case refresh
    case search
    case publish
    case subscribe
    case update
    case desktopCache = "desktop_cache"
    case exportMarkdown = "export_markdown"
    case exportDatabase = "export_database"
    case remoteArchive = "remote_archive"
    case cloudPublish = "cloud_publish"
    case maintain
}

public enum CrawlQueryActionResolver {
    public static func action(for manifest: CrawlAppManifest, queryArguments: [String]) -> String? {
        if Self.queryLooksLikeSQL(queryArguments) {
            return ["query", "sql"].first { manifest.commands[$0] != nil }
        }
        if manifest.commands["search"] != nil {
            return "search"
        }
        if manifest.commands["query"] != nil {
            return "query"
        }
        return nil
    }

    private static func queryLooksLikeSQL(_ arguments: [String]) -> Bool {
        let query = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["select ", "with ", "pragma ", "explain "].contains { query.hasPrefix($0) }
    }
}

public enum CrawlAppState: String, Codable, Equatable, Sendable {
    case current
    case stale
    case syncing
    case needsConfig = "needs_config"
    case needsAuth = "needs_auth"
    case error
    case disabled
    case unknown
}

public struct CrawlCount: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var value: Int

    public init(id: String, label: String, value: Int) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct CrawlFreshness: Codable, Equatable, Sendable {
    public var status: CrawlAppState
    public var ageSeconds: Int?
    public var staleAfterSeconds: Int?

    public init(status: CrawlAppState, ageSeconds: Int? = nil, staleAfterSeconds: Int? = nil) {
        self.status = status
        self.ageSeconds = ageSeconds
        self.staleAfterSeconds = staleAfterSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case ageSeconds = "age_seconds"
        case staleAfterSeconds = "stale_after_seconds"
    }
}

public struct CrawlShareStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var repoPath: String?
    public var remote: String?
    public var branch: String?
    public var needsUpdate: Bool?

    public init(enabled: Bool, repoPath: String? = nil, remote: String? = nil, branch: String? = nil, needsUpdate: Bool? = nil) {
        self.enabled = enabled
        self.repoPath = repoPath
        self.remote = remote
        self.branch = branch
        self.needsUpdate = needsUpdate
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case repoPath = "repo_path"
        case remote
        case branch
        case needsUpdate = "needs_update"
    }
}

public struct CrawlRemoteStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var mode: String?
    public var endpoint: String?
    public var archive: String?
    public var lastIngestAt: Date?
    public var lastSyncAt: Date?
    public var needsUpdate: Bool?

    public init(
        enabled: Bool,
        mode: String? = nil,
        endpoint: String? = nil,
        archive: String? = nil,
        lastIngestAt: Date? = nil,
        lastSyncAt: Date? = nil,
        needsUpdate: Bool? = nil)
    {
        self.enabled = enabled
        self.mode = mode
        self.endpoint = endpoint
        self.archive = archive
        self.lastIngestAt = lastIngestAt
        self.lastSyncAt = lastSyncAt
        self.needsUpdate = needsUpdate
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case endpoint
        case archive
        case lastIngestAt = "last_ingest_at"
        case lastSyncAt = "last_sync_at"
        case needsUpdate = "needs_update"
    }
}

public struct CrawlSQLiteObjectStatus: Codable, Equatable, Sendable {
    public var key: String?
    public var contentType: String?
    public var bytes: Int?
    public var uploadedAt: Date?

    public init(key: String? = nil, contentType: String? = nil, bytes: Int? = nil, uploadedAt: Date? = nil) {
        self.key = key
        self.contentType = contentType
        self.bytes = bytes
        self.uploadedAt = uploadedAt
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case contentType = "content_type"
        case bytes
        case uploadedAt = "uploaded_at"
    }
}

public struct CrawlSQLiteBundleStatus: Codable, Equatable, Sendable {
    public var key: String?
    public var contentType: String?
    public var format: String?
    public var compression: String?
    public var rawBytes: Int?
    public var compressedBytes: Int?
    public var partCount: Int?
    public var uploadedAt: Date?
    public var generatedAt: Date?

    public init(
        key: String? = nil,
        contentType: String? = nil,
        format: String? = nil,
        compression: String? = nil,
        rawBytes: Int? = nil,
        compressedBytes: Int? = nil,
        partCount: Int? = nil,
        uploadedAt: Date? = nil,
        generatedAt: Date? = nil)
    {
        self.key = key
        self.contentType = contentType
        self.format = format
        self.compression = compression
        self.rawBytes = rawBytes
        self.compressedBytes = compressedBytes
        self.partCount = partCount
        self.uploadedAt = uploadedAt
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case contentType = "content_type"
        case format
        case compression
        case rawBytes = "raw_bytes"
        case compressedBytes = "compressed_bytes"
        case partCount = "part_count"
        case uploadedAt = "uploaded_at"
        case generatedAt = "generated_at"
    }
}

public enum CrawlDatabaseKind: String, Codable, Equatable, Sendable {
    case sqlite
    case cache
    case logical
    case remote
    case d1
    case cloudflareD1 = "cloudflare-d1"
    case sqliteBundle = "sqlite_bundle"
}

public struct CrawlDatabaseResource: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var kind: CrawlDatabaseKind
    public var role: String?
    public var path: String?
    public var endpoint: String?
    public var archive: String?
    public var isPrimary: Bool
    public var bytes: Int?
    public var modifiedAt: Date?
    public var counts: [CrawlCount]

    public init(
        id: String,
        label: String,
        kind: CrawlDatabaseKind,
        role: String? = nil,
        path: String? = nil,
        endpoint: String? = nil,
        archive: String? = nil,
        isPrimary: Bool = false,
        bytes: Int? = nil,
        modifiedAt: Date? = nil,
        counts: [CrawlCount] = [])
    {
        self.id = id
        self.label = label
        self.kind = kind
        self.role = role
        self.path = path
        self.endpoint = endpoint
        self.archive = archive
        self.isPrimary = isPrimary
        self.bytes = bytes
        self.modifiedAt = modifiedAt
        self.counts = counts
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case kind
        case role
        case path
        case endpoint
        case archive
        case isPrimary = "is_primary"
        case bytes
        case modifiedAt = "modified_at"
        case counts
    }
}

public struct CrawlAppStatus: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var appID: CrawlAppID
    public var generatedAt: Date
    public var state: CrawlAppState
    public var summary: String
    public var configPath: String?
    public var databasePath: String?
    public var databaseBytes: Int?
    public var walBytes: Int?
    public var lastSyncAt: Date?
    public var lastImportAt: Date?
    public var lastExportAt: Date?
    public var counts: [CrawlCount]
    public var databases: [CrawlDatabaseResource]
    public var freshness: CrawlFreshness?
    public var share: CrawlShareStatus?
    public var remote: CrawlRemoteStatus?
    public var sqliteObject: CrawlSQLiteObjectStatus?
    public var sqliteBundle: CrawlSQLiteBundleStatus?
    public var warnings: [String]
    public var errors: [String]

    public var id: CrawlAppID {
        self.appID
    }

    public init(
        schemaVersion: Int = 1,
        appID: CrawlAppID,
        generatedAt: Date = Date(),
        state: CrawlAppState,
        summary: String,
        configPath: String? = nil,
        databasePath: String? = nil,
        databaseBytes: Int? = nil,
        walBytes: Int? = nil,
        lastSyncAt: Date? = nil,
        lastImportAt: Date? = nil,
        lastExportAt: Date? = nil,
        counts: [CrawlCount] = [],
        databases: [CrawlDatabaseResource] = [],
        freshness: CrawlFreshness? = nil,
        share: CrawlShareStatus? = nil,
        remote: CrawlRemoteStatus? = nil,
        sqliteObject: CrawlSQLiteObjectStatus? = nil,
        sqliteBundle: CrawlSQLiteBundleStatus? = nil,
        warnings: [String] = [],
        errors: [String] = [])
    {
        self.schemaVersion = schemaVersion
        self.appID = appID
        self.generatedAt = generatedAt
        self.state = state
        self.summary = summary
        self.configPath = configPath
        self.databasePath = databasePath
        self.databaseBytes = databaseBytes
        self.walBytes = walBytes
        self.lastSyncAt = lastSyncAt
        self.lastImportAt = lastImportAt
        self.lastExportAt = lastExportAt
        self.counts = counts
        self.databases = databases
        self.freshness = freshness
        self.share = share
        self.remote = remote
        self.sqliteObject = sqliteObject
        self.sqliteBundle = sqliteBundle
        self.warnings = warnings
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case appID = "app_id"
        case generatedAt = "generated_at"
        case state
        case summary
        case configPath = "config_path"
        case databasePath = "database_path"
        case databaseBytes = "database_bytes"
        case walBytes = "wal_bytes"
        case lastSyncAt = "last_sync_at"
        case lastImportAt = "last_import_at"
        case lastExportAt = "last_export_at"
        case counts
        case databases
        case freshness
        case share
        case remote
        case sqliteObject = "sqlite_object"
        case sqliteBundle = "sqlite_bundle"
        case warnings
        case errors
    }
}

public extension CrawlAppStatus {
    var isRecoverableGraincrawlSourceFailure: Bool {
        guard self.appID == BuiltInCrawlApps.graincrawlID, self.state == .error else { return false }
        guard !Self.summaryLooksLikeActionFailure(self.summary) else { return false }
        let text = ([self.summary] + self.errors + self.warnings)
            .joined(separator: "\n")
            .lowercased()
        return text.contains("granola access token")
            || text.contains("unsupported cache version")
            || text.contains("private-api reports")
            || text.contains("desktop-cache reports")
    }

    func mergingActionFailure(_ failure: CrawlAppStatus) -> CrawlAppStatus {
        guard self.appID == failure.appID else { return failure }
        return CrawlAppStatus(
            schemaVersion: self.schemaVersion,
            appID: self.appID,
            generatedAt: failure.generatedAt,
            state: failure.state,
            summary: failure.summary,
            configPath: self.configPath,
            databasePath: self.databasePath,
            databaseBytes: self.databaseBytes,
            walBytes: self.walBytes,
            lastSyncAt: self.lastSyncAt,
            lastImportAt: self.lastImportAt,
            lastExportAt: self.lastExportAt,
            counts: self.counts,
            databases: self.databases,
            freshness: self.freshness,
            share: self.share,
            remote: self.remote,
            sqliteObject: self.sqliteObject,
            sqliteBundle: self.sqliteBundle,
            warnings: Self.mergedMessages(failure.warnings, self.warnings),
            errors: Self.mergedMessages(failure.errors, self.errors))
    }

    static func commandFailure(
        appID: CrawlAppID,
        action: String? = nil,
        message: String?,
        fallback: String)
        -> CrawlAppStatus
    {
        let fullMessage = message?.nilIfBlank ?? fallback
        let normalized = Self.normalizedCommandFailure(appID: appID, message: fullMessage)
        let summary = [action?.nilIfBlank, normalized.summary].compactMap { $0 }.joined(separator: ": ")
        return CrawlAppStatus(
            appID: appID,
            state: normalized.state,
            summary: summary,
            errors: [normalized.summary])
    }

    static func richestMetadataStatus(_ preferred: CrawlAppStatus?, fallback: CrawlAppStatus?) -> CrawlAppStatus? {
        guard let preferred else { return fallback }
        guard let fallback else { return preferred }
        return preferred.metadataScore >= fallback.metadataScore ? preferred : fallback
    }

    private var metadataScore: Int {
        var score = 0
        score += self.configPath == nil ? 0 : 1
        score += self.databasePath == nil ? 0 : 1
        score += self.databaseBytes == nil ? 0 : 1
        score += self.walBytes == nil ? 0 : 1
        score += self.lastSyncAt == nil ? 0 : 1
        score += self.lastImportAt == nil ? 0 : 1
        score += self.lastExportAt == nil ? 0 : 1
        score += self.counts.isEmpty ? 0 : 2
        score += self.databases.isEmpty ? 0 : 3
        score += self.freshness == nil ? 0 : 1
        score += self.share == nil ? 0 : 2
        score += self.remote == nil ? 0 : 3
        score += self.sqliteObject == nil ? 0 : 2
        score += self.sqliteBundle == nil ? 0 : 3
        return score
    }

    private static func mergedMessages(_ primary: [String], _ secondary: [String]) -> [String] {
        var seen = Set<String>()
        var messages: [String] = []
        for message in primary + secondary {
            guard !seen.contains(message) else { continue }
            seen.insert(message)
            messages.append(message)
        }
        return messages
    }

    private static func summaryLooksLikeActionFailure(_ summary: String) -> Bool {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "refresh:",
            "sync:",
            "desktop-cache-import:",
            "doctor:",
            "unlock:",
            "query:",
            "search:",
            "export-md:",
        ].contains { trimmed.hasPrefix($0) }
    }

    private static func normalizedCommandFailure(appID: CrawlAppID, message: String) -> (state: CrawlAppState, summary: String) {
        let lowered = message.lowercased()
        if appID == BuiltInCrawlApps.gitcrawlID,
           lowered.contains("github"),
           (lowered.contains("bad credentials") || lowered.contains("status 401") || lowered.contains("401"))
        {
            return (.needsAuth, "GitHub credentials rejected")
        }
        if appID == BuiltInCrawlApps.birdclawID,
           lowered.contains("no twitter cookies")
               || lowered.contains("no x cookies")
               || lowered.contains("missing credentials")
               || lowered.contains("missing auth_token")
               || lowered.contains("missing ct0")
        {
            return (.needsAuth, "X browser cookies not found")
        }
        if appID == BuiltInCrawlApps.gogcliID,
           lowered.contains("credentials") || lowered.contains("auth")
        {
            return (.needsAuth, "Google account needs auth")
        }
        return (.error, Self.firstUsefulFailureLine(in: message) ?? "Command failed")
    }

    private static func firstUsefulFailureLine(in message: String) -> String? {
        message.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                guard !line.isEmpty else { return false }
                return !Self.isRequestTraceLine(line)
            }
    }

    private static func isRequestTraceLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.hasPrefix("[github] request ")
            || lowered.hasPrefix("[slack] request ")
            || lowered.hasPrefix("[notion] request ")
            || lowered.hasPrefix("[discord] request ")
            || lowered.hasPrefix("[granola] request ")
    }
}

public struct CrawlAppInstallation: Codable, Equatable, Sendable, Identifiable {
    public var manifest: CrawlAppManifest
    public var binaryPath: String?
    public var configPathOverride: String?
    public var configValues: [String: String]
    public var staleAfterSeconds: Int?
    public var enabled: Bool

    public var id: CrawlAppID {
        self.manifest.id
    }

    public init(
        manifest: CrawlAppManifest,
        binaryPath: String? = nil,
        configPathOverride: String? = nil,
        configValues: [String: String] = [:],
        staleAfterSeconds: Int? = nil,
        enabled: Bool = true)
    {
        self.manifest = manifest
        self.binaryPath = binaryPath
        self.configPathOverride = configPathOverride
        self.configValues = configValues
        self.staleAfterSeconds = staleAfterSeconds
        self.enabled = enabled
    }
}

public enum CrawlActionID: String, Codable, Hashable, Sendable {
    case status
    case doctor
    case refresh
    case publish
    case update
    case desktopCacheImport = "desktop-cache-import"
    case exportMarkdown = "export-md"
}

public struct CrawlCommandResult: Codable, Equatable, Sendable {
    public var appID: CrawlAppID
    public var action: String
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var startedAt: Date
    public var finishedAt: Date

    public var succeeded: Bool {
        self.exitCode == 0
    }

    public init(
        appID: CrawlAppID,
        action: String,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        startedAt: Date,
        finishedAt: Date)
    {
        self.appID = appID
        self.action = action
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public extension CrawlCommandResult {
    var userFacingRunMessage: String? {
        if self.succeeded {
            return Self.firstLine(in: self.stderr)
        }
        return CrawlAppStatus.commandFailure(
            appID: self.appID,
            message: self.stderr.nilIfBlank ?? self.stdout.nilIfBlank,
            fallback: "\(self.action) failed with exit \(self.exitCode)")
            .summary
    }

    var shouldShowExitCode: Bool {
        !self.succeeded
    }

    private static func firstLine(in output: String) -> String? {
        output.nilIfBlank?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }
}
