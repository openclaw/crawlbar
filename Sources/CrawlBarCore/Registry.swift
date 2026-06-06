import Foundation

public struct CrawlAppRegistry: @unchecked Sendable {
    private let configStore: CrawlBarConfigStore
    private let catalog: CrawlManifestCatalog
    private let resolver: CrawlExecutableResolver
    private let nativeConfigStore: CrawlNativeConfigStore

    public init(
        configStore: CrawlBarConfigStore = CrawlBarConfigStore(),
        catalog: CrawlManifestCatalog = CrawlManifestCatalog(),
        resolver: CrawlExecutableResolver = CrawlExecutableResolver(),
        nativeConfigStore: CrawlNativeConfigStore = CrawlNativeConfigStore())
    {
        self.configStore = configStore
        self.catalog = catalog
        self.resolver = resolver
        self.nativeConfigStore = nativeConfigStore
    }

    public func loadConfig(includeSecrets: Bool = false) throws -> CrawlBarConfig {
        try self.configStore.loadOrCreateDefault(includeSecrets: includeSecrets)
    }

    public func installations(includeDisabled: Bool = true, includeSecrets: Bool = false) throws -> [CrawlAppInstallation] {
        let loadedConfig = try self.loadConfig()
        let manifests = Dictionary(uniqueKeysWithValues: self.catalog
            .manifests(config: loadedConfig)
            .map { ($0.id, $0) })
        let knownIDs = manifests.keys.sorted()
        let config = loadedConfig.normalized(knownIDs: knownIDs)
        return config.apps.compactMap { appConfig in
            guard let manifest = manifests[appConfig.id] else { return nil }
            let nativeAppConfig = self.appConfigWithNativeValues(
                appConfig,
                manifest: manifest,
                includeSecrets: includeSecrets)
            let isAvailable = manifest.availability == .available
            let enabled = isAvailable && nativeAppConfig.enabled
            guard includeDisabled || enabled else { return nil }
            let executionKind = manifest.executionKind(configValues: nativeAppConfig.configValues)
            let defaultBinary = executionKind == .ssh
                ? "ssh"
                : Self.effectiveBinaryName(manifest: manifest, configValues: nativeAppConfig.configValues)
            let requestedBinary = executionKind == .ssh
                ? defaultBinary
                : nativeAppConfig.binaryPath?.nilIfBlank ?? defaultBinary
            let resolvedBinary = isAvailable ? self.resolver.resolve(requestedBinary) : nil
            let resolvedAppConfig = includeSecrets && enabled && resolvedBinary != nil
                ? self.configStore.appConfigWithSecrets(nativeAppConfig, manifest: manifest)
                : nativeAppConfig
            let refreshFrequency = resolvedAppConfig.refreshFrequency ?? config.refreshFrequency
            let staleAfterSeconds = resolvedAppConfig.autoRefreshEnabled ? refreshFrequency.seconds.map(Int.init) : nil
            return CrawlAppInstallation(
                manifest: manifest,
                binaryPath: resolvedBinary,
                configPathOverride: resolvedAppConfig.configPath,
                configValues: resolvedAppConfig.configValues,
                staleAfterSeconds: staleAfterSeconds,
                enabled: enabled)
        }
    }

    public func installationsForStatus(includeDisabled: Bool = true) throws -> [CrawlAppInstallation] {
        try self.installations(includeDisabled: includeDisabled, includeSecrets: false).map { installation in
            guard installation.enabled,
                  installation.binaryPath != nil,
                  installation.manifest.needsSecretsForStatus
            else { return installation }
            return self.installationWithSecrets(installation)
        }
    }

    public func installation(for id: CrawlAppID, includeSecrets: Bool = false) throws -> CrawlAppInstallation? {
        try self.installations(includeDisabled: true, includeSecrets: includeSecrets).first { $0.id == id }
    }

    public func installationForStatus(for id: CrawlAppID) throws -> CrawlAppInstallation? {
        guard let installation = try self.installation(for: id, includeSecrets: false) else { return nil }
        guard installation.enabled,
              installation.binaryPath != nil,
              installation.manifest.needsSecretsForStatus
        else { return installation }
        return self.installationWithSecrets(installation)
    }

    public func availableInstallations(includeSecrets: Bool = false) throws -> [CrawlAppInstallation] {
        try self.installations(includeDisabled: false, includeSecrets: includeSecrets).filter { $0.binaryPath != nil }
    }

    public func appConfigWithNativeValues(
        _ appConfig: CrawlBarAppConfig,
        manifest: CrawlAppManifest,
        includeSecrets: Bool = true)
        -> CrawlBarAppConfig
    {
        var copy = appConfig
        copy.configValues = self.nativeConfigStore.resolvedConfigValues(
            appConfig: appConfig,
            manifest: manifest,
            includeSecrets: includeSecrets)
        return copy
    }

    private func installationWithSecrets(_ installation: CrawlAppInstallation) -> CrawlAppInstallation {
        let appConfig = CrawlBarAppConfig(
            id: installation.id,
            enabled: installation.enabled,
            configPath: installation.configPathOverride,
            configValues: installation.configValues)
        let nativeConfig = self.appConfigWithNativeValues(
            appConfig,
            manifest: installation.manifest,
            includeSecrets: true)
        let secretConfig = self.configStore.appConfigWithSecrets(nativeConfig, manifest: installation.manifest)
        return CrawlAppInstallation(
            manifest: installation.manifest,
            binaryPath: installation.binaryPath,
            configPathOverride: installation.configPathOverride,
            configValues: secretConfig.configValues,
            staleAfterSeconds: installation.staleAfterSeconds,
            enabled: installation.enabled)
    }

    private static func effectiveBinaryName(manifest: CrawlAppManifest, configValues: [String: String]) -> String {
        guard manifest.id == BuiltInCrawlApps.birdclawID else {
            return manifest.binary.name
        }
        let accessPath = (configValues["access_path"]?.nilIfBlank ?? "bird")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return accessPath == "birdclaw" ? "birdclaw" : manifest.binary.name
    }
}
