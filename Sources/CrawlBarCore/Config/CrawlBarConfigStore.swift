import Foundation

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

    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".crawlbar", isDirectory: true)
            .appendingPathComponent("config.json")
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
}
