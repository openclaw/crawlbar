import CrawlBarCore
import Foundation

extension CrawlBarSettingsModel {
    func load() {
        do {
            self.apply(try Self.loadSnapshot())
        } catch {
            CrawlBarLog.config.error("Settings load failed: \(error.localizedDescription, privacy: .public)")
            self.lastError = error.localizedDescription
        }
    }

    func loadForPresentation(onLoaded: @escaping @MainActor () -> Void) {
        self.loadTask?.cancel()
        let generation = UUID()
        self.loadGeneration = generation
        self.isLoading = true
        self.lastError = nil
        self.loadTask = Task.detached {
            let snapshot = Result { try Self.loadSnapshot() }
            await MainActor.run {
                guard self.loadGeneration == generation else { return }
                self.isLoading = false
                self.loadTask = nil
                switch snapshot {
                case .success(let snapshot):
                    self.apply(snapshot)
                    onLoaded()
                case .failure(let error):
                    CrawlBarLog.config.error("Settings load failed: \(error.localizedDescription, privacy: .public)")
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func save() {
        self.pendingSaveTask?.cancel()
        self.pendingSaveTask = nil
        self.persist()
    }

    func scrubSecretConfigValues() {
        var scrubbedApps = self.apps
        for index in scrubbedApps.indices {
            guard let manifest = self.installations[scrubbedApps[index].id]?.manifest else { continue }
            for option in manifest.configOptions where option.kind == .secret {
                scrubbedApps[index].configValues.removeValue(forKey: option.id)
            }
        }
        self.apps = scrubbedApps
    }

    func saveDebounced() {
        self.pendingSaveTask?.cancel()
        self.pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self.persist()
            self.pendingSaveTask = nil
        }
    }

    func configValueDidChange(appID: CrawlAppID, option: CrawlAppManifest.ConfigOption, value: String?) {
        if option.kind == .secret {
            if value?.nilIfBlank == nil {
                self.clearedNativeSecretIDsByAppID[appID, default: []].insert(option.id)
            } else {
                self.clearedNativeSecretIDsByAppID[appID]?.remove(option.id)
            }
        }
        self.saveDebounced()
    }

    func persist() {
        guard self.hasLoadedSnapshot, !self.isLoading else { return }
        do {
            let config = CrawlBarConfig(
                refreshFrequency: self.refreshFrequency,
                manifestDirectories: self.manifestDirectories,
                apps: self.apps)
            try self.store.save(
                config,
                clearMissingSecretIDsByAppID: self.clearedNativeSecretIDsByAppID)
            try self.nativeConfigStore.write(
                config: config,
                clearMissingSecretIDsByAppID: self.clearedNativeSecretIDsByAppID)
            self.clearedNativeSecretIDsByAppID = [:]
            self.lastError = nil
            CrawlBarStateBroadcast.configDidChange()
        } catch {
            CrawlBarLog.config.error("Settings save failed: \(error.localizedDescription, privacy: .public)")
            self.lastError = error.localizedDescription
        }
    }

    func apply(_ snapshot: CrawlBarSettingsSnapshot) {
        self.hasLoadedSnapshot = true
        self.apps = snapshot.apps
        self.refreshFrequency = snapshot.refreshFrequency
        self.manifestDirectories = snapshot.manifestDirectories
        self.installations = snapshot.installations
        self.recentResults = snapshot.recentResults
        self.manifestDiagnostics = snapshot.manifestDiagnostics
        if !self.sidebarSelectionIsValid {
            self.selectedSidebarItem = self.apps.first.map { .crawler($0.id) } ?? .general
        }
        self.lastError = nil
    }

    nonisolated static func loadSnapshot() throws -> CrawlBarSettingsSnapshot {
        let store = CrawlBarConfigStore()
        let registry = CrawlAppRegistry()
        let nativeConfigStore = CrawlNativeConfigStore()
        let logStore = CrawlActionLogStore()
        let config = try store.loadOrCreateDefault()
        let loadedInstallations = try registry.installations(includeDisabled: true)
        let manifests = Dictionary(uniqueKeysWithValues: loadedInstallations.map { ($0.id, $0.manifest) })
        let appConfigsByID = Dictionary(uniqueKeysWithValues: config.apps.map { ($0.id, $0) })
        let installationsByID = Dictionary(uniqueKeysWithValues: loadedInstallations.map { ($0.id, $0) })
        let apps = loadedInstallations.map { installation in
            let appConfig = appConfigsByID[installation.id] ?? CrawlBarAppConfig(
                id: installation.id,
                enabled: installation.manifest.availability == .available,
                showInMenuBar: installation.manifest.availability == .available)
            guard let manifest = manifests[appConfig.id] else { return appConfig }
            var copy = appConfig
            copy.configValues = nativeConfigStore.resolvedConfigValues(
                appConfig: appConfig,
                manifest: manifest,
                includeSecrets: false)
            return copy
        }
        return CrawlBarSettingsSnapshot(
            apps: Self.sortedAppConfigs(apps, installationsByID: installationsByID),
            refreshFrequency: config.refreshFrequency,
            manifestDirectories: config.manifestDirectories,
            installations: installationsByID,
            recentResults: Self.recentResults(logStore: logStore),
            manifestDiagnostics: CrawlManifestCatalog().diagnostics(config: config))
    }

    nonisolated static func sortedAppConfigs(
        _ apps: [CrawlBarAppConfig],
        installationsByID: [CrawlAppID: CrawlAppInstallation])
        -> [CrawlBarAppConfig]
    {
        let originalIndex = Dictionary(uniqueKeysWithValues: apps.enumerated().map { ($0.element.id, $0.offset) })
        return apps.sorted { lhs, rhs in
            let lhsRank = Self.sidebarRank(installation: installationsByID[lhs.id])
            let rhsRank = Self.sidebarRank(installation: installationsByID[rhs.id])
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return (originalIndex[lhs.id] ?? Int.max) < (originalIndex[rhs.id] ?? Int.max)
        }
    }

    nonisolated static func recentResults(logStore: CrawlActionLogStore) -> [CrawlAppID: CrawlCommandResult] {
        var resultsByApp: [CrawlAppID: CrawlCommandResult] = [:]
        for result in logStore.recentResults(limit: 200).sorted(by: { $0.finishedAt > $1.finishedAt }) {
            if resultsByApp[result.appID] == nil {
                resultsByApp[result.appID] = result
            }
        }
        return resultsByApp
    }

    nonisolated static func sidebarRank(installation: CrawlAppInstallation?) -> Int {
        guard let installation else { return 4 }
        if installation.manifest.availability == .comingSoon { return 3 }
        if installation.binaryPath != nil { return 0 }
        if installation.manifest.install != nil { return 1 }
        return 2
    }
}

struct CrawlBarSettingsSnapshot: Sendable {
    let apps: [CrawlBarAppConfig]
    let refreshFrequency: RefreshFrequency
    let manifestDirectories: [String]
    let installations: [CrawlAppID: CrawlAppInstallation]
    let recentResults: [CrawlAppID: CrawlCommandResult]
    let manifestDiagnostics: [CrawlManifestDiagnostic]
}
