import Foundation

public enum RefreshFrequency: String, Codable, CaseIterable, Sendable {
    case manual
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case hourly = "1h"

    public var seconds: TimeInterval? {
        switch self {
        case .manual:
            nil
        case .fiveMinutes:
            300
        case .fifteenMinutes:
            900
        case .thirtyMinutes:
            1_800
        case .hourly:
            3_600
        }
    }
}

public struct CrawlBarAppConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: CrawlAppID
    public var enabled: Bool
    public var binaryPath: String?
    public var configPath: String?
    public var refreshFrequency: RefreshFrequency?
    public var preferredRefreshAction: String?
    public var autoRefreshEnabled: Bool
    public var shareEnabled: Bool
    public var shareAfterRefresh: Bool
    public var preferredShareAction: String?
    public var preferredUpdateAction: String?
    public var showInMenuBar: Bool
    public var configValues: [String: String]

    public init(
        id: CrawlAppID,
        enabled: Bool = true,
        binaryPath: String? = nil,
        configPath: String? = nil,
        refreshFrequency: RefreshFrequency? = nil,
        preferredRefreshAction: String? = "refresh",
        autoRefreshEnabled: Bool = false,
        shareEnabled: Bool = false,
        shareAfterRefresh: Bool = false,
        preferredShareAction: String? = "publish",
        preferredUpdateAction: String? = "update",
        showInMenuBar: Bool = true,
        configValues: [String: String] = [:])
    {
        self.id = id
        self.enabled = enabled
        self.binaryPath = binaryPath
        self.configPath = configPath
        self.refreshFrequency = refreshFrequency
        self.preferredRefreshAction = preferredRefreshAction
        self.autoRefreshEnabled = autoRefreshEnabled
        self.shareEnabled = shareEnabled
        self.shareAfterRefresh = shareAfterRefresh
        self.preferredShareAction = preferredShareAction
        self.preferredUpdateAction = preferredUpdateAction
        self.showInMenuBar = showInMenuBar
        self.configValues = configValues
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case binaryPath = "binary_path"
        case configPath = "config_path"
        case refreshFrequency = "refresh_frequency"
        case preferredRefreshAction = "preferred_refresh_action"
        case autoRefreshEnabled = "auto_refresh_enabled"
        case shareEnabled = "share_enabled"
        case shareAfterRefresh = "share_after_refresh"
        case preferredShareAction = "preferred_share_action"
        case preferredUpdateAction = "preferred_update_action"
        case showInMenuBar = "show_in_menu_bar"
        case configValues = "config_values"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(CrawlAppID.self, forKey: .id)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.binaryPath = try container.decodeIfPresent(String.self, forKey: .binaryPath)
        self.configPath = try container.decodeIfPresent(String.self, forKey: .configPath)
        self.refreshFrequency = try container.decodeIfPresent(RefreshFrequency.self, forKey: .refreshFrequency)
        self.preferredRefreshAction = try container.decodeIfPresent(String.self, forKey: .preferredRefreshAction) ?? "refresh"
        self.autoRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRefreshEnabled) ?? false
        self.shareEnabled = try container.decodeIfPresent(Bool.self, forKey: .shareEnabled) ?? false
        self.shareAfterRefresh = try container.decodeIfPresent(Bool.self, forKey: .shareAfterRefresh) ?? false
        self.preferredShareAction = try container.decodeIfPresent(String.self, forKey: .preferredShareAction) ?? "publish"
        self.preferredUpdateAction = try container.decodeIfPresent(String.self, forKey: .preferredUpdateAction) ?? "update"
        self.showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        self.configValues = try container.decodeIfPresent([String: String].self, forKey: .configValues) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encodeIfPresent(self.binaryPath, forKey: .binaryPath)
        try container.encodeIfPresent(self.configPath, forKey: .configPath)
        try container.encodeIfPresent(self.refreshFrequency, forKey: .refreshFrequency)
        try container.encodeIfPresent(self.preferredRefreshAction, forKey: .preferredRefreshAction)
        try container.encode(self.autoRefreshEnabled, forKey: .autoRefreshEnabled)
        try container.encode(self.shareEnabled, forKey: .shareEnabled)
        try container.encode(self.shareAfterRefresh, forKey: .shareAfterRefresh)
        try container.encodeIfPresent(self.preferredShareAction, forKey: .preferredShareAction)
        try container.encodeIfPresent(self.preferredUpdateAction, forKey: .preferredUpdateAction)
        try container.encode(self.showInMenuBar, forKey: .showInMenuBar)
        if !self.configValues.isEmpty {
            try container.encode(self.configValues, forKey: .configValues)
        }
    }
}

public struct CrawlBarConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var refreshFrequency: RefreshFrequency
    public var manifestDirectories: [String]
    public var apps: [CrawlBarAppConfig]

    public init(
        version: Int = Self.currentVersion,
        refreshFrequency: RefreshFrequency = .fifteenMinutes,
        manifestDirectories: [String] = ["~/.crawlbar/apps"],
        apps: [CrawlBarAppConfig] = [])
    {
        self.version = version
        self.refreshFrequency = refreshFrequency
        self.manifestDirectories = manifestDirectories
        self.apps = apps
    }

    public func normalized(knownIDs: [CrawlAppID] = BuiltInCrawlApps.all.map(\.id)) -> CrawlBarConfig {
        var seen: Set<CrawlAppID> = []
        var normalizedApps: [CrawlBarAppConfig] = []
        for var app in self.apps where !seen.contains(app.id) {
            seen.insert(app.id)
            if BuiltInCrawlApps.manifest(for: app.id)?.availability == .comingSoon {
                app.enabled = false
                app.showInMenuBar = false
                app.autoRefreshEnabled = false
                app.shareEnabled = false
                app.shareAfterRefresh = false
            } else if self.version < 2, Self.newlyAvailableAppIDs.contains(app.id), !app.enabled, !app.showInMenuBar {
                app.enabled = true
                app.showInMenuBar = true
            }
            normalizedApps.append(app)
        }
        for id in knownIDs where !seen.contains(id) {
            let enabled = BuiltInCrawlApps.manifest(for: id)?.availability != .comingSoon
            normalizedApps.append(CrawlBarAppConfig(id: id, enabled: enabled, showInMenuBar: enabled))
        }
        return CrawlBarConfig(
            version: Self.currentVersion,
            refreshFrequency: self.refreshFrequency,
            manifestDirectories: self.manifestDirectories.isEmpty ? ["~/.crawlbar/apps"] : self.manifestDirectories,
            apps: normalizedApps)
    }

    private static let newlyAvailableAppIDs: Set<CrawlAppID> = [
        BuiltInCrawlApps.gogcliID,
        BuiltInCrawlApps.wacliID,
    ]

    public func appConfig(for id: CrawlAppID) -> CrawlBarAppConfig? {
        self.apps.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case refreshFrequency = "refresh_frequency"
        case manifestDirectories = "manifest_directories"
        case apps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        self.refreshFrequency = try container.decodeIfPresent(RefreshFrequency.self, forKey: .refreshFrequency) ?? .fifteenMinutes
        self.manifestDirectories = try container.decodeIfPresent([String].self, forKey: .manifestDirectories) ?? ["~/.crawlbar/apps"]
        self.apps = try container.decodeIfPresent([CrawlBarAppConfig].self, forKey: .apps) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.refreshFrequency, forKey: .refreshFrequency)
        try container.encode(self.manifestDirectories, forKey: .manifestDirectories)
        try container.encode(self.apps, forKey: .apps)
    }
}

public enum CrawlBarConfigStoreError: LocalizedError {
    case decodeFailed(String)
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .decodeFailed(details):
            "Failed to decode CrawlBar config: \(details)"
        case let .encodeFailed(details):
            "Failed to encode CrawlBar config: \(details)"
        }
    }
}

public struct CrawlBarConfigStore: @unchecked Sendable {
    public var fileURL: URL
    private let fileManager: FileManager
    private let secretStore: CrawlSecretStore
    private let cache: CrawlBarConfigCache

    public init(
        fileURL: URL = Self.defaultURL(),
        fileManager: FileManager = .default,
        secretStore: CrawlSecretStore = CrawlSecretStore(),
        cache: CrawlBarConfigCache = .shared)
    {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.secretStore = secretStore
        self.cache = cache
    }

    public func load(includeSecrets: Bool = false) throws -> CrawlBarConfig? {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }
        let modificationDate = self.modificationDate(for: self.fileURL)
        if !includeSecrets,
           let cached = self.cache.config(path: self.fileURL.path, modificationDate: modificationDate)
        {
            return cached
        }
        let data = try Data(contentsOf: self.fileURL)
        do {
            let config = try CrawlCoding.makeJSONDecoder().decode(CrawlBarConfig.self, from: data).normalized()
            if !includeSecrets {
                self.cache.set(config, path: self.fileURL.path, modificationDate: modificationDate)
            }
            return includeSecrets ? self.configWithSecrets(config) : config
        } catch {
            throw CrawlBarConfigStoreError.decodeFailed(error.localizedDescription)
        }
    }

    public func loadOrCreateDefault(includeSecrets: Bool = false) throws -> CrawlBarConfig {
        if let existing = try self.load(includeSecrets: includeSecrets) {
            return existing
        }
        let config = CrawlBarConfig().normalized()
        try self.save(config)
        return config
    }

    public func save(_ config: CrawlBarConfig, clearMissingSecretIDsByAppID: [CrawlAppID: Set<String>] = [:]) throws {
        let normalized = config.normalized()
        let persisted = try self.configForDisk(normalized, clearMissingSecretIDsByAppID: clearMissingSecretIDsByAppID)
        let data: Data
        do {
            data = try CrawlCoding.makeJSONEncoder().encode(persisted)
        } catch {
            throw CrawlBarConfigStoreError.encodeFailed(error.localizedDescription)
        }
        let directory = self.fileURL.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: self.fileURL, options: [.atomic])
        #if os(macOS) || os(Linux)
        try self.fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: self.fileURL.path)
        #endif
        self.cache.set(persisted, path: self.fileURL.path, modificationDate: self.modificationDate(for: self.fileURL))
    }

    private func configWithSecrets(_ config: CrawlBarConfig) -> CrawlBarConfig {
        let manifests = self.manifestsByID(config: config)
        var copy = config
        for index in copy.apps.indices {
            guard let manifest = manifests[copy.apps[index].id] else { continue }
            copy.apps[index] = self.appConfigWithSecrets(copy.apps[index], manifest: manifest)
        }
        return copy
    }

    public func appConfigWithSecrets(_ appConfig: CrawlBarAppConfig, manifest: CrawlAppManifest) -> CrawlBarAppConfig {
        var copy = appConfig
        for option in manifest.configOptions where option.kind == .secret {
            guard copy.configValues[option.id]?.nilIfBlank == nil else { continue }
            do {
                if let value = try self.secretStore.value(appID: copy.id, optionID: option.id)?.nilIfBlank {
                    copy.configValues[option.id] = value
                }
            } catch {
                CrawlBarLog.keychain.error(
                    "Keychain read failed for \(copy.id.rawValue, privacy: .public).\(option.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return copy
    }

    private func configForDisk(
        _ config: CrawlBarConfig,
        clearMissingSecretIDsByAppID: [CrawlAppID: Set<String>] = [:])
        throws -> CrawlBarConfig
    {
        let manifests = self.manifestsByID(config: config)
        var copy = config
        for index in copy.apps.indices {
            guard let manifest = manifests[copy.apps[index].id] else { continue }
            for option in manifest.configOptions where option.kind == .secret {
                if let value = copy.apps[index].configValues.removeValue(forKey: option.id) {
                    try self.secretStore.set(value.nilIfBlank, appID: copy.apps[index].id, optionID: option.id)
                } else if clearMissingSecretIDsByAppID[copy.apps[index].id]?.contains(option.id) == true {
                    try self.secretStore.set(nil, appID: copy.apps[index].id, optionID: option.id)
                }
            }
        }
        return copy
    }

    private func manifestsByID(config: CrawlBarConfig) -> [CrawlAppID: CrawlAppManifest] {
        Dictionary(uniqueKeysWithValues: CrawlManifestCatalog(fileManager: self.fileManager)
            .manifests(config: config)
            .map { ($0.id, $0) })
    }

    private func modificationDate(for url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".crawlbar", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}

public final class CrawlBarConfigCache: @unchecked Sendable {
    public static let shared = CrawlBarConfigCache()

    private struct Entry {
        var modificationDate: Date?
        var config: CrawlBarConfig
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    func config(path: String, modificationDate: Date?) -> CrawlBarConfig? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let entry = self.entries[path], entry.modificationDate == modificationDate else {
            return nil
        }
        return entry.config
    }

    func set(_ config: CrawlBarConfig, path: String, modificationDate: Date?) {
        self.lock.lock()
        self.entries[path] = Entry(modificationDate: modificationDate, config: config)
        self.lock.unlock()
    }
}

public enum PathExpander {
    public static func expandHome(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: home).appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }
}
