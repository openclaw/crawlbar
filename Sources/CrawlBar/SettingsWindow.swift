import AppKit
import CrawlBarCore
import SwiftUI

@MainActor
final class CrawlBarSettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: CrawlBarSettingsModel?
    var onClose: (() -> Void)?

    func show(appID: CrawlAppID? = nil) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            CrawlBarLog.app.debug("Opened settings in \(elapsedMilliseconds, privacy: .public)ms")
        }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            if let appID,
               let model = (window.contentView as? NSHostingView<CrawlBarSettingsView>)?.rootView.model
            {
                model.selectedAppID = appID
            }
            if let model = self.model {
                self.refreshStatusAfterPresentation(model: model, window: window)
            }
            return
        }

        let model: CrawlBarSettingsModel
        if let cachedModel = self.model {
            model = cachedModel
        } else {
            model = CrawlBarSettingsModel(loadImmediately: false)
            self.model = model
        }
        if let appID {
            model.selectedAppID = appID
        } else if model.selectedSidebarItem == nil {
            model.selectedSidebarItem = .general
        }
        model.isLoading = true
        model.lastError = nil
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CrawlBarSettingsLayout.minWindowWidth,
                height: CrawlBarSettingsLayout.minWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "CrawlBar Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentMinSize = NSSize(
            width: CrawlBarSettingsLayout.minWindowWidth,
            height: CrawlBarSettingsLayout.minWindowHeight)
        window.contentView = NSHostingView(rootView: CrawlBarSettingsView(model: model))
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        self.window = window
        model.loadForPresentation { [weak self, weak window] in
            guard let self, let window else { return }
            self.refreshStatusAfterPresentation(model: model, window: window)
        }
    }

    private func refreshStatusAfterPresentation(model: CrawlBarSettingsModel, window: NSWindow) {
        guard !model.isRefreshing else { return }
        Task { @MainActor in
            await Task.yield()
            guard self.window === window else { return }
            model.refreshAll()
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.model?.save()
            self.model?.scrubSecretConfigValues()
            self.window = nil
            self.onClose?()
        }
    }
}

@MainActor
final class CrawlBarSettingsModel: NSObject, ObservableObject {
    @Published var apps: [CrawlBarAppConfig] = []
    @Published var refreshFrequency: RefreshFrequency = .fifteenMinutes
    @Published fileprivate var selectedSidebarItem: CrawlBarSettingsSidebarItem?
    var selectedAppID: CrawlAppID? {
        get {
            guard case let .crawler(id) = self.selectedSidebarItem else { return nil }
            return id
        }
        set {
            self.selectedSidebarItem = newValue.map(CrawlBarSettingsSidebarItem.crawler)
        }
    }
    @Published var statuses: [CrawlAppID: CrawlAppStatus] = [:]
    @Published var installations: [CrawlAppID: CrawlAppInstallation] = [:]
    @Published var isRefreshing = false
    @Published var isInstallingCLI = false
    @Published var appActionMessage: String?
    @Published var runningActions: [CrawlAppID: String] = [:]
    @Published var actionMessages: [CrawlAppID: String] = [:]
    @Published var recentResults: [CrawlAppID: CrawlCommandResult] = [:]
    @Published var lastError: String?
    @Published var manifestDiagnostics: [CrawlManifestDiagnostic] = []
    @Published var isLoading = false
    @Published fileprivate var manifestDirectories: [String] = ["~/.crawlbar/apps"]

    private var refreshTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var pendingSaveTask: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var loadGeneration = UUID()
    private var recentResultsGeneration = UUID()
    private var hasLoadedSnapshot = false
    private var clearedNativeSecretIDsByAppID: [CrawlAppID: Set<String>] = [:]
    private let store = CrawlBarConfigStore()
    private let registry = CrawlAppRegistry()
    private let runner: CrawlCommandRunner
    private let statusService: CrawlStatusService
    private let nativeConfigStore = CrawlNativeConfigStore()
    private let installer = CrawlInstaller()
    private let logStore = CrawlActionLogStore()

    init(loadImmediately: Bool = true) {
        let runner = CrawlCommandRunner()
        self.runner = runner
        self.statusService = CrawlStatusService(runner: runner)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(Self.statusesDidChange(_:)),
            name: .crawlBarStatusesDidChange,
            object: nil)
        if loadImmediately {
            self.load()
        } else {
            self.selectedSidebarItem = .general
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private var sidebarSelectionIsValid: Bool {
        switch self.selectedSidebarItem {
        case .general:
            true
        case .crawler(let id):
            self.apps.contains { $0.id == id }
        case nil:
            false
        }
    }

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

    private func persist() {
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

    func refreshAll() {
        self.loadRecentResultsAsync()
        self.refreshTask?.cancel()
        let generation = UUID()
        self.refreshGeneration = generation
        self.isRefreshing = true
        let registry = self.registry
        let statusService = self.statusService
        self.refreshTask = Task.detached {
            let installations = (try? registry.installationsForStatus(includeDisabled: true)) ?? []
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                let installationsByID = Dictionary(uniqueKeysWithValues: installations.map { ($0.id, $0) })
                self.installations = installationsByID
                self.apps = Self.sortedAppConfigs(self.apps, installationsByID: installationsByID)
            }
            let partitioned = Self.partitionStatuses(installations: installations, statusService: statusService)
            if !partitioned.immediate.isEmpty {
                await MainActor.run {
                    guard self.refreshGeneration == generation else { return }
                    for status in partitioned.immediate {
                        self.statuses[status.appID] = status
                    }
                    CrawlBarStateBroadcast.statusesDidChange(Dictionary(uniqueKeysWithValues: partitioned.immediate.map { ($0.appID, $0) }))
                }
            }
            await withTaskGroup(of: CrawlAppStatus.self) { group in
                for installation in partitioned.commandInstallations {
                    group.addTask {
                        guard !Task.isCancelled else {
                            return CrawlAppStatus(appID: installation.id, state: .unknown, summary: "Refresh cancelled")
                        }
                        return statusService.status(for: installation, timeoutSeconds: 5)
                    }
                }
                for await status in group {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        guard self.refreshGeneration == generation else { return }
                        self.statuses[status.appID] = status
                        CrawlBarStateBroadcast.statusesDidChange([status.appID: status])
                    }
                }
            }
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                self.isRefreshing = false
                self.refreshTask = nil
            }
        }
    }

    nonisolated private static func partitionStatuses(
        installations: [CrawlAppInstallation],
        statusService: CrawlStatusService)
        -> (immediate: [CrawlAppStatus], commandInstallations: [CrawlAppInstallation])
    {
        var immediate: [CrawlAppStatus] = []
        var commandInstallations: [CrawlAppInstallation] = []
        for installation in installations {
            if let status = statusService.immediateStatus(for: installation) {
                immediate.append(status)
            } else {
                commandInstallations.append(installation)
            }
        }
        return (immediate, commandInstallations)
    }

    func runAction(_ action: String, appID: CrawlAppID) {
        guard let installation = self.installations[appID] else { return }
        self.runningActions[appID] = action
        self.actionMessages[appID] = "Running \(Self.actionTitle(action))..."
        let runner = self.runner
        let statusService = self.statusService
        let logStore = self.logStore
        let registry = self.registry
        Task.detached {
            let actionInstallation = (try? registry.installation(for: appID, includeSecrets: true)) ?? installation
            let message: String
            var actionError: CrawlAppStatus?
            do {
                CrawlBarLog.actions.notice("Running \(action, privacy: .public) for \(appID.rawValue, privacy: .public) from settings")
                let result = try runner.run(installation: actionInstallation, action: action, timeoutSeconds: 600)
                _ = try? logStore.save(result)
                message = result.exitCode == 0
                    ? "\(Self.actionTitle(action)) finished"
                    : "\(Self.actionTitle(action)) failed with exit \(result.exitCode)"
                if !result.succeeded {
                    CrawlBarLog.actions.error(
                        "\(action, privacy: .public) for \(appID.rawValue, privacy: .public) failed with exit \(result.exitCode)")
                    actionError = Self.actionFailureStatus(result)
                }
            } catch {
                CrawlBarLog.actions.error(
                    "\(action, privacy: .public) for \(appID.rawValue, privacy: .public) threw: \(error.localizedDescription, privacy: .public)")
                message = error.localizedDescription
                actionError = Self.actionFailureStatus(appID: appID, action: action, message: error.localizedDescription)
            }
            let refreshedStatus = statusService.status(for: actionInstallation, timeoutSeconds: 5)
            await MainActor.run {
                let status = actionError.map {
                    Self.actionFailureStatus($0, refreshedStatus: refreshedStatus, currentStatus: self.statuses[appID])
                } ?? refreshedStatus
                self.statuses[appID] = status
                CrawlBarStateBroadcast.statusesDidChange([appID: status])
                self.runningActions[appID] = nil
                self.actionMessages[appID] = message
                self.loadRecentResults()
            }
        }
    }

    private func loadRecentResults() {
        self.recentResultsGeneration = UUID()
        self.recentResults = Self.recentResults(logStore: self.logStore)
    }

    private func loadRecentResultsAsync() {
        let logStore = self.logStore
        let generation = UUID()
        self.recentResultsGeneration = generation
        Task.detached {
            let results = Self.recentResults(logStore: logStore)
            await MainActor.run {
                guard self.recentResultsGeneration == generation else { return }
                self.recentResults = results
            }
        }
    }

    private func mergeStatuses(_ incoming: [CrawlAppID: CrawlAppStatus]) {
        for (appID, status) in incoming {
            self.statuses[appID] = status
        }
    }

    @objc private func statusesDidChange(_ notification: Notification) {
        guard let statuses = CrawlBarStateBroadcast.statuses(from: notification) else { return }
        self.mergeStatuses(statuses)
    }

    func installApp(_ appID: CrawlAppID) {
        guard let installation = self.installations[appID] else { return }
        self.runningActions[appID] = "install"
        self.actionMessages[appID] = "Installing \(installation.manifest.binary.name)..."
        let installer = self.installer
        let logStore = self.logStore
        let registry = self.registry
        Task.detached {
            let message: String
            do {
                let result = try installer.install(installation)
                _ = try? logStore.save(result)
                message = "\(installation.manifest.binary.name) installed"
            } catch {
                message = error.localizedDescription
            }
            let installations = (try? registry.installations(includeDisabled: true)) ?? []
            await MainActor.run {
                let installationsByID = Dictionary(uniqueKeysWithValues: installations.map { ($0.id, $0) })
                self.installations = installationsByID
                self.apps = Self.sortedAppConfigs(self.apps, installationsByID: installationsByID)
                self.runningActions[appID] = nil
                self.actionMessages[appID] = message
            }
        }
    }

    func backupDatabases(_ appID: CrawlAppID) {
        guard let status = self.statuses[appID] else { return }
        self.runningActions[appID] = "backup"
        self.actionMessages[appID] = "Backing up databases..."
        Task.detached {
            let message: String
            do {
                let backup = try CrawlDatabaseBackupStore.backup(status: status)
                message = "Backed up \(backup.files.count) database file(s)"
            } catch {
                message = error.localizedDescription
            }
            await MainActor.run {
                self.runningActions[appID] = nil
                self.actionMessages[appID] = message
            }
        }
    }

    func openDataFolder(_ appID: CrawlAppID) {
        guard let status = self.statuses[appID],
              let path = status.databases.first(where: { $0.isPrimary })?.path ?? status.databasePath
        else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: PathExpander.expandHome(path)).deletingLastPathComponent())
    }

    func openConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([self.store.fileURL])
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(CrawlActionLogStore.defaultDirectory())
    }

    func installCLI() {
        self.isInstallingCLI = true
        self.appActionMessage = "Installing crawlbar CLI..."
        Task.detached {
            let message: String
            do {
                let path = try Self.installBundledCLI()
                message = "Installed crawlbar CLI at \(path)"
            } catch {
                message = error.localizedDescription
            }
            await MainActor.run {
                self.isInstallingCLI = false
                self.appActionMessage = message
            }
        }
    }

    nonisolated private static func actionTitle(_ action: String) -> String {
        switch action {
        case "refresh":
            "Sync"
        case "doctor":
            "Doctor"
        case "unlock":
            "Unlock"
        case "publish":
            "Publish"
        case "cloud-publish":
            "Cloud Publish"
        case "remote-status":
            "Remote Status"
        case "remote-archives":
            "Remote Archives"
        case "update":
            "Update"
        case "desktop-cache-import":
            "Desktop Import"
        default:
            action
        }
    }

    nonisolated private static func sortedAppConfigs(
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

    private func apply(_ snapshot: CrawlBarSettingsSnapshot) {
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

    nonisolated private static func loadSnapshot() throws -> CrawlBarSettingsSnapshot {
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

    nonisolated private static func recentResults(logStore: CrawlActionLogStore) -> [CrawlAppID: CrawlCommandResult] {
        var resultsByApp: [CrawlAppID: CrawlCommandResult] = [:]
        for result in logStore.recentResults(limit: 200).sorted(by: { $0.finishedAt > $1.finishedAt }) {
            if resultsByApp[result.appID] == nil {
                resultsByApp[result.appID] = result
            }
        }
        return resultsByApp
    }

    nonisolated private static func sidebarRank(installation: CrawlAppInstallation?) -> Int {
        guard let installation else { return 4 }
        if installation.manifest.availability == .comingSoon { return 3 }
        if installation.binaryPath != nil { return 0 }
        if installation.manifest.install != nil { return 1 }
        return 2
    }

    nonisolated private static func actionFailureStatus(_ result: CrawlCommandResult) -> CrawlAppStatus {
        let fallback = "\(result.action) failed with exit \(result.exitCode)"
        return CrawlAppStatus.commandFailure(
            appID: result.appID,
            action: result.action,
            message: result.stderr.nilIfBlank ?? result.stdout.nilIfBlank,
            fallback: fallback)
    }

    nonisolated private static func actionFailureStatus(appID: CrawlAppID, action: String, message: String) -> CrawlAppStatus {
        CrawlAppStatus.commandFailure(
            appID: appID,
            action: action,
            message: message,
            fallback: "\(action) failed")
    }

    nonisolated private static func actionFailureStatus(
        _ failure: CrawlAppStatus,
        refreshedStatus: CrawlAppStatus?,
        currentStatus: CrawlAppStatus?)
        -> CrawlAppStatus
    {
        guard let metadataStatus = CrawlAppStatus.richestMetadataStatus(refreshedStatus, fallback: currentStatus) else {
            return failure
        }
        return metadataStatus.mergingActionFailure(failure)
    }

    nonisolated private static func installBundledCLI() throws -> String {
        let fileManager = FileManager.default
        let sourceCandidates = Self.cliSourceCandidates()
        guard let source = sourceCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw CrawlBarSettingsError.cliHelperMissing
        }
        let destinationDirectory = URL(fileURLWithPath: PathExpander.expandHome("~/.local/bin"), isDirectory: true)
        let destination = destinationDirectory.appendingPathComponent("crawlbar")
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination.path
    }

    nonisolated private static func cliSourceCandidates() -> [URL] {
        var candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/crawlbar"),
        ]
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDirectory.appendingPathComponent("crawlbarctl"))
            candidates.append(executableDirectory.deletingLastPathComponent().appendingPathComponent("debug/crawlbarctl"))
            candidates.append(executableDirectory.deletingLastPathComponent().appendingPathComponent("release/crawlbarctl"))
        }
        return candidates
    }
}

private enum CrawlBarSettingsError: LocalizedError {
    case cliHelperMissing

    var errorDescription: String? {
        switch self {
        case .cliHelperMissing:
            "Could not find bundled crawlbar CLI helper"
        }
    }
}

fileprivate enum CrawlBarSettingsSidebarItem: Hashable {
    case general
    case crawler(CrawlAppID)
}

private struct CrawlBarSettingsSnapshot: Sendable {
    let apps: [CrawlBarAppConfig]
    let refreshFrequency: RefreshFrequency
    let manifestDirectories: [String]
    let installations: [CrawlAppID: CrawlAppInstallation]
    let recentResults: [CrawlAppID: CrawlCommandResult]
    let manifestDiagnostics: [CrawlManifestDiagnostic]
}

private enum CrawlBarSettingsLayout {
    static let minWindowWidth: CGFloat = 1120
    static let minWindowHeight: CGFloat = 790
    static let sidebarWidth: CGFloat = 250
    static let detailHorizontalPadding: CGFloat = 22
    static let detailVerticalPadding: CGFloat = 18
    static let detailBottomPadding: CGFloat = 16
}

struct CrawlBarSettingsView: View {
    @ObservedObject var model: CrawlBarSettingsModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: self.animatedColumnVisibility) {
            List(selection: self.sidebarSelection) {
                Section("CrawlBar") {
                    CrawlBarGeneralSidebarRow(isSelected: self.model.selectedSidebarItem == .general)
                        .tag(CrawlBarSettingsSidebarItem.general as CrawlBarSettingsSidebarItem?)
                        .contentShape(Rectangle())
                        .listRowBackground(CrawlBarSidebarSelectionBackground(isSelected: self.model.selectedSidebarItem == .general))
                        .onTapGesture {
                            self.model.selectedSidebarItem = .general
                        }
                }
                Section("Crawlers") {
                    ForEach(self.model.apps) { app in
                        let item = CrawlBarSettingsSidebarItem.crawler(app.id)
                        CrawlBarSidebarRow(
                            app: app,
                            manifest: self.model.installations[app.id]?.manifest,
                            status: self.model.statuses[app.id],
                            binaryPath: self.model.installations[app.id]?.binaryPath,
                            isSelected: self.model.selectedSidebarItem == item)
                            .tag(item as CrawlBarSettingsSidebarItem?)
                            .contentShape(Rectangle())
                            .listRowBackground(CrawlBarSidebarSelectionBackground(isSelected: self.model.selectedSidebarItem == item))
                            .onTapGesture {
                                self.model.selectedSidebarItem = item
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(CrawlBarSettingsLayout.sidebarWidth)
        } detail: {
            self.detailContainer
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: CrawlBarSettingsLayout.minWindowWidth,
            maxWidth: .infinity,
            minHeight: CrawlBarSettingsLayout.minWindowHeight,
            maxHeight: .infinity,
            alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarSelection: Binding<CrawlBarSettingsSidebarItem?> {
        Binding(
            get: { self.model.selectedSidebarItem },
            set: { item in
                guard let item else { return }
                self.model.selectedSidebarItem = item
            })
    }

    private var animatedColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { self.columnVisibility },
            set: { visibility in
                withAnimation(.easeInOut(duration: 0.22)) {
                    self.columnVisibility = visibility
                }
            })
    }

    @ViewBuilder
    private var detailContainer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = self.model.lastError {
                CrawlBarSettingsErrorBanner(message: error)
                    .padding(.horizontal, CrawlBarSettingsLayout.detailHorizontalPadding)
                    .padding(.top, CrawlBarSettingsLayout.detailVerticalPadding)
                    .padding(.bottom, 12)
            }
            self.selectedDetail
                .disabled(self.model.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if self.model.isLoading && self.model.apps.isEmpty {
            ProgressView("Loading settings...")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            switch self.model.selectedSidebarItem {
            case .general:
                CrawlBarGeneralSettingsView(model: self.model)
            case .crawler(let selectedID):
                if self.model.apps.contains(where: { $0.id == selectedID })
                {
                    CrawlBarAppDetailView(
                        app: self.binding(for: selectedID),
                        globalRefreshFrequency: self.model.refreshFrequency,
                        installation: self.model.installations[selectedID],
                        status: self.model.statuses[selectedID],
                        latestResult: self.model.recentResults[selectedID],
                        isRefreshing: self.model.isRefreshing,
                        runningAction: self.model.runningActions[selectedID],
                        actionMessage: self.model.actionMessages[selectedID],
                        refreshStatus: { self.model.refreshAll() },
                        runAction: { action in self.model.runAction(action, appID: selectedID) },
                        installApp: { self.model.installApp(selectedID) },
                        backupDatabases: { self.model.backupDatabases(selectedID) },
                        openDataFolder: { self.model.openDataFolder(selectedID) },
                        configValueChanged: { option, value in self.model.configValueDidChange(appID: selectedID, option: option, value: value) },
                        save: { self.model.save() },
                        saveDebounced: { self.model.saveDebounced() })
                        .padding(.horizontal, CrawlBarSettingsLayout.detailHorizontalPadding)
                        .padding(.vertical, CrawlBarSettingsLayout.detailVerticalPadding)
                } else {
                    ContentUnavailableView(
                        "No crawler selected",
                        systemImage: "sidebar.left")
                }
            case nil:
                ContentUnavailableView(
                    "No crawler selected",
                    systemImage: "sidebar.left")
            }
        }
    }

    private func binding(for id: CrawlAppID) -> Binding<CrawlBarAppConfig> {
        Binding(
            get: {
                self.model.apps.first(where: { $0.id == id }) ?? CrawlBarAppConfig(id: id)
            },
            set: {
                guard let index = self.model.apps.firstIndex(where: { $0.id == id }) else { return }
                self.model.apps[index] = $0
            })
    }

}

private struct CrawlBarSettingsErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(self.message)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CrawlBarGeneralSettingsView: View {
    @ObservedObject var model: CrawlBarSettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CrawlBar")
                            .font(.title3.weight(.semibold))
                        Text("Menu bar control plane for local crawler apps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        self.model.refreshAll()
                    } label: {
                        Label("Refresh All", systemImage: "arrow.clockwise")
                    }
                    .disabled(self.model.isRefreshing)
                }

                CrawlBarPanel(title: "App") {
                    HStack(spacing: 8) {
                        Button {
                            self.model.installCLI()
                        } label: {
                            Label("Install CLI", systemImage: "terminal")
                        }
                        .disabled(self.model.isInstallingCLI)
                        Button {
                            self.model.openConfigFile()
                        } label: {
                            Label("Open Config", systemImage: "doc.text")
                        }
                        Button {
                            self.model.openLogsFolder()
                        } label: {
                            Label("Open Logs", systemImage: "folder")
                        }
                    }
                    .controlSize(.small)
                    CrawlBarFact(label: "CLI install path", value: "~/.local/bin/crawlbar")
                    CrawlBarFact(label: "Config", value: CrawlBarConfigStore().fileURL.path)
                    if let message = self.model.appActionMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                CrawlBarPanel(title: "Scheduling") {
                    CrawlBarControlRow(
                        title: "Default schedule",
                        caption: "Used by crawlers that inherit the global sync interval.")
                    {
                        Picker("Default schedule", selection: self.$model.refreshFrequency) {
                            ForEach(RefreshFrequency.allCases, id: \.self) { frequency in
                                Text(CrawlBarFrequencyLabel.text(for: frequency)).tag(frequency)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .onChange(of: self.model.refreshFrequency) {
                            self.model.save()
                        }
                    }
                }

                CrawlBarPanel(title: "Discovery") {
                    ForEach(self.manifestDirectories, id: \.self) { directory in
                        CrawlBarFact(label: "Manifest Directory", value: directory)
                    }
                    if !self.model.manifestDiagnostics.isEmpty {
                        Divider()
                        ForEach(self.model.manifestDiagnostics) { diagnostic in
                            Label {
                                Text("\(diagnostic.path): \(diagnostic.message)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }

                CrawlBarPanel(title: "Crawler Inventory") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            CrawlBarFact(label: "Ready", value: "\(self.readyCount)")
                            CrawlBarFact(label: "Missing CLI", value: "\(self.missingCount)")
                            CrawlBarFact(label: "Coming Soon", value: "\(self.comingSoonCount)")
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.bottom, CrawlBarSettingsLayout.detailBottomPadding)
        }
        .padding(.horizontal, CrawlBarSettingsLayout.detailHorizontalPadding)
        .padding(.vertical, CrawlBarSettingsLayout.detailVerticalPadding)
    }

    private var manifestDirectories: [String] {
        self.model.manifestDirectories
    }

    private var readyCount: Int {
        self.model.installations.values.filter { $0.manifest.availability == .available && $0.binaryPath != nil }.count
    }

    private var missingCount: Int {
        self.model.installations.values.filter { $0.manifest.availability == .available && $0.binaryPath == nil }.count
    }

    private var comingSoonCount: Int {
        self.model.installations.values.filter { $0.manifest.availability == .comingSoon }.count
    }
}

struct CrawlBarGeneralSidebarRow: View {
    let isSelected: Bool

    var body: some View {
        Label("General", systemImage: "gearshape")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(self.isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CrawlBarSidebarSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        if self.isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.82))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        } else {
            Color.clear
        }
    }
}

struct CrawlBarSidebarRow: View {
    let app: CrawlBarAppConfig
    let manifest: CrawlAppManifest?
    let status: CrawlAppStatus?
    let binaryPath: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(CrawlBarCrawlerTitle.text(for: self.app.id, manifest: self.manifest))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(self.isSelected ? Color.white : Color.primary)
                        .lineLimit(1)
                    CrawlBarStatusDot(state: self.rowState)
                }
                Text(self.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(self.subtitleColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .opacity(self.manifest?.availability == .comingSoon ? 0.58 : 1)
    }

    private var rowState: CrawlAppState {
        if self.manifest?.availability == .comingSoon { return .disabled }
        if !self.app.enabled { return .disabled }
        if self.binaryPath == nil { return .needsConfig }
        let state = self.status?.state ?? .unknown
        if self.status?.isRecoverableGraincrawlSourceFailure == true {
            return .stale
        }
        return state
    }

    private var subtitle: String {
        let binaryName = self.manifest?.binary.name ?? self.app.id.rawValue
        if self.manifest?.availability == .comingSoon { return "\(binaryName) · coming soon" }
        if !self.app.enabled { return "Disabled" }
        if self.binaryPath == nil { return "Missing \(binaryName)" }
        if self.rowState == .needsAuth {
            return self.status?.summary ?? "Needs auth"
        }
        if self.rowState == .error {
            return self.status?.summary ?? "Error"
        }
        if self.rowState == .current,
           self.status?.freshness?.status == .stale
        {
            return "Status current"
        }
        if let syncedAt = self.syncedAt {
            return "Synced \(CrawlBarDateText.relative(syncedAt))"
        }
        switch self.rowState {
        case .syncing:
            return "Syncing"
        case .stale:
            return "Needs refresh"
        case .unknown:
            return "Waiting for status"
        default:
            return self.status == nil ? "Waiting for status" : "Status current"
        }
    }

    private var syncedAt: Date? {
        if let lastSyncAt = self.status?.lastSyncAt {
            return lastSyncAt
        }
        if let primaryModifiedAt = self.status?.databases.first(where: { $0.isPrimary })?.modifiedAt {
            return primaryModifiedAt
        }
        return self.status?.databases.compactMap(\.modifiedAt).max()
    }

    private var subtitleColor: Color {
        if self.isSelected { return Color.white.opacity(0.78) }
        switch self.rowState {
        case .needsConfig, .needsAuth, .error:
            return Color.red
        case .stale where self.app.id == BuiltInCrawlApps.graincrawlID && self.status?.state == .error:
            return Color.yellow
        default:
            return Color.secondary
        }
    }
}

struct CrawlBarAppDetailView: View {
    @Binding var app: CrawlBarAppConfig
    let globalRefreshFrequency: RefreshFrequency
    let installation: CrawlAppInstallation?
    let status: CrawlAppStatus?
    let latestResult: CrawlCommandResult?
    let isRefreshing: Bool
    let runningAction: String?
    let actionMessage: String?
    let refreshStatus: () -> Void
    let runAction: (String) -> Void
    let installApp: () -> Void
    let backupDatabases: () -> Void
    let openDataFolder: () -> Void
    let configValueChanged: (CrawlAppManifest.ConfigOption, String?) -> Void
    let save: () -> Void
    let saveDebounced: () -> Void

    private var manifest: CrawlAppManifest? { self.installation?.manifest ?? BuiltInCrawlApps.manifest(for: self.app.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.header
            if self.isComingSoon {
                self.comingSoonContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 6)
            } else if self.isMissingBinary {
                self.notInstalledContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        self.statusSection
                        self.dataSection
                        self.syncSection
                        self.configurationSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(CrawlBarCrawlerTitle.text(for: self.app.id, manifest: self.manifest))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    CrawlBarStatusPill(state: self.effectiveState)
                }
                Text(self.manifest?.description ?? self.app.id.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, alignment: .leading)
            Spacer()
            HStack(spacing: 6) {
                if !self.isComingSoon {
                    Button(action: self.refreshStatus) {
                        Image(systemName: self.isRefreshing ? "hourglass" : "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh status")
                }
            }
            .controlSize(.small)
        }
    }

    private var comingSoonContent: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 44)
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 72, height: 72)
            Text("\(self.manifest?.displayName ?? "This crawler") has not shipped yet")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("CrawlBar will let you know when it is ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var notInstalledContent: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 44)
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 72, height: 72)
            Text("\(CrawlBarCrawlerTitle.text(for: self.app.id, manifest: self.manifest)) is not installed")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Install \(self.manifest?.binary.name ?? self.app.id.rawValue) to enable sync, search, and status checks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if self.manifest?.install != nil {
                Button {
                    self.installApp()
                } label: {
                    Label("Install", systemImage: "square.and.arrow.down")
                }
                .disabled(self.runningAction != nil)
            }
            if self.runningAction == "install" {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var statusSection: some View {
        CrawlBarDetailSection(title: "Status") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 260), spacing: 14, alignment: .top),
                    GridItem(.flexible(minimum: 260), spacing: 14, alignment: .top),
                ],
                alignment: .leading,
                spacing: 14)
            {
                self.statusSummary
                self.sourceSummary
                self.latestRunSummary
            }
        }
    }

    private var dataSection: some View {
        CrawlBarDetailSection(title: "Data") {
            self.remoteStore
            if !self.usesRemoteStore {
                self.databases
            }
            self.metrics
        }
    }

    private var syncSection: some View {
        CrawlBarDetailSection(title: "Sync") {
            self.syncSettings
            self.cloudArchiveSettings
            self.gitShareSettings
        }
    }

    private var configurationSection: some View {
        CrawlBarDetailSection(title: "Configuration") {
            self.configuration
            self.paths
            self.privacy
        }
    }

    private var statusSummary: some View {
        CrawlBarPanel(title: "Status") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    CrawlBarFact(label: "Current", value: self.status?.summary ?? self.statusFallback)
                    CrawlBarFact(label: "Last Sync", value: self.lastSyncSummary)
                }
                GridRow {
                    CrawlBarFact(
                        label: "Databases",
                        value: self.databaseSummary)
                    CrawlBarFact(label: "Binary", value: self.binarySummary)
                }
            }
            if let issue = self.primaryIssue {
                CrawlBarIssueBanner(message: issue, state: self.issueState)
            }
        }
    }

    private var sourceSummary: some View {
        CrawlBarPanel(title: "Sources") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    CrawlBarFact(label: "Refresh", value: self.refreshSourceSummary)
                    CrawlBarFact(label: "Archive", value: self.archiveSourceSummary)
                }
                GridRow {
                    CrawlBarFact(label: "Snapshot", value: self.snapshotSummary)
                    CrawlBarFact(label: "Config", value: self.configSourceSummary)
                }
            }
        }
    }

    private var latestRunSummary: some View {
        CrawlBarPanel(title: "Latest Run") {
            if let latestResult {
                HStack(spacing: 8) {
                    CrawlBarStatusDot(state: latestResult.succeeded ? .current : .error)
                    Text(Self.actionTitle(latestResult.action))
                        .font(.callout.weight(.medium))
                    Text(latestResult.succeeded ? "finished" : "failed")
                        .font(.callout)
                        .foregroundStyle(latestResult.succeeded ? Color.secondary : Color.red)
                    Spacer(minLength: 8)
                    Text(CrawlBarDateText.relative(latestResult.finishedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if latestResult.shouldShowExitCode {
                    CrawlBarFact(label: "Exit", value: "\(latestResult.exitCode)")
                }
                if let output = latestResult.userFacingRunMessage {
                    Text(output)
                        .font(.caption)
                        .foregroundStyle(latestResult.succeeded ? Color.secondary : Color.red)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            } else {
                Text("No action logs yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var remoteStore: some View {
        if let remoteStore = self.remoteStoreSummary {
            CrawlBarPanel(title: remoteStore.title) {
                CrawlBarFact(label: "Remote", value: remoteStore.remote)
                if let archive = remoteStore.archive {
                    CrawlBarFact(label: "Archive", value: archive)
                }
                if let repoPath = remoteStore.repoPath {
                    CrawlBarFact(label: "Checkout", value: repoPath)
                }
                if let branch = remoteStore.branch {
                    CrawlBarFact(label: "Branch", value: branch)
                }
                if let bundle = remoteStore.bundle {
                    CrawlBarFact(label: "Bundle", value: bundle)
                }
                if let compressed = remoteStore.compressed {
                    CrawlBarFact(label: "Compressed", value: compressed)
                }
                if let parts = remoteStore.parts {
                    CrawlBarFact(label: "Parts", value: parts)
                }
                if let lastIngest = remoteStore.lastIngest {
                    CrawlBarFact(label: "Ingest", value: lastIngest)
                }
                if let databasePath = self.status?.databasePath {
                    CrawlBarFact(label: "Local index", value: URL(fileURLWithPath: databasePath).lastPathComponent)
                }
            }
        }
    }

    @ViewBuilder
    private var databases: some View {
        if let databases = self.status?.databases, !databases.isEmpty {
            CrawlBarPanel(title: "Databases") {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        self.openDataFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open data folder")
                    Button {
                        self.backupDatabases()
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .buttonStyle(.borderless)
                    .disabled(self.runningAction != nil)
                    .accessibilityLabel("Back up database files")
                    Text("\(databases.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(spacing: 0) {
                    ForEach(databases) { database in
                        CrawlBarDatabaseRow(database: database)
                        if database.id != databases.last?.id {
                            Divider()
                                .padding(.leading, 28)
                        }
                    }
                }
            }
        } else {
            CrawlBarPanel(title: "Databases") {
                Label("No database metadata yet", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        if !self.overviewCounts.isEmpty {
            CrawlBarPanel(title: "Counts") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Spacer(minLength: 0)
                    Text(self.overviewDataScope)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(self.overviewCounts) { count in
                        CrawlBarMetricRow(label: count.label, value: "\(count.value)")
                        if count.id != self.overviewCounts.last?.id {
                            Divider()
                        }
                    }
                }
            }
        } else {
            CrawlBarPanel(title: "Counts") {
                Label("No count metrics yet", systemImage: "number")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syncSettings: some View {
        CrawlBarPanel(title: "Sync") {
            VStack(alignment: .leading, spacing: 10) {
                CrawlBarSwitchRow(
                    title: "Enable crawler",
                    caption: "Allow CrawlBar to run actions and show live status.",
                    isOn: self.$app.enabled)
                    .onChange(of: self.app.enabled) { self.save() }
                CrawlBarSwitchRow(
                    title: "Show in menu bar",
                    caption: "Include this crawler in the menu bar status menu.",
                    isOn: self.$app.showInMenuBar)
                    .disabled(!self.app.enabled)
                    .onChange(of: self.app.showInMenuBar) { self.save() }
                CrawlBarSwitchRow(
                    title: "Run on schedule",
                    caption: "Refresh this crawler automatically in the background.",
                    isOn: self.$app.autoRefreshEnabled)
                    .disabled(!self.app.enabled)
                    .onChange(of: self.app.autoRefreshEnabled) { self.save() }
                CrawlBarSwitchRow(
                    title: "Use default schedule",
                    caption: "Follow the global interval from General settings.",
                    isOn: self.usesGlobalRefreshBinding)
                    .disabled(!self.app.enabled || !self.app.autoRefreshEnabled)
            }
            CrawlBarControlRow(
                title: "Custom schedule",
                caption: "Overrides the global interval for this crawler.")
            {
                Picker("Custom schedule", selection: self.refreshFrequencyBinding) {
                    ForEach(RefreshFrequency.allCases, id: \.self) { frequency in
                        Text(CrawlBarFrequencyLabel.text(for: frequency)).tag(frequency)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            .disabled(!self.app.enabled || !self.app.autoRefreshEnabled || self.app.refreshFrequency == nil)
            Text("Default schedule: \(CrawlBarFrequencyLabel.text(for: self.globalRefreshFrequency))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if self.installation?.binaryPath == nil, self.manifest?.install != nil {
                    Button {
                        self.installApp()
                    } label: {
                        Label("Install", systemImage: "square.and.arrow.down")
                    }
                }
                if self.commandAvailable(self.app.preferredRefreshAction ?? "refresh") {
                    Button {
                        self.runAction(self.app.preferredRefreshAction ?? "refresh")
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                if self.commandAvailable("desktop-cache-import") {
                    Button {
                        self.runAction("desktop-cache-import")
                    } label: {
                        Label("Import Desktop", systemImage: "externaldrive.connected.to.line.below")
                    }
                }
                if self.commandAvailable("doctor") {
                    Button {
                        self.runAction("doctor")
                    } label: {
                        Label("Run Doctor", systemImage: "stethoscope")
                    }
                }
                if self.commandAvailable("unlock") {
                    Button {
                        self.runAction("unlock")
                    } label: {
                        Label("Unlock", systemImage: "key")
                    }
                }
                if self.nativeAppAvailable {
                    Button {
                        self.openNativeApp()
                    } label: {
                        Label("Open Source App", systemImage: "app")
                    }
                }
                if self.commandAvailable(self.app.preferredUpdateAction ?? "update") {
                    Button {
                        self.runAction(self.app.preferredUpdateAction ?? "update")
                    } label: {
                        Label("Update", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .disabled(self.runningAction != nil)
            if let runningAction {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running \(runningAction)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gitShareSettings: some View {
        CrawlBarPanel(title: "Git Snapshot") {
            CrawlBarSwitchRow(
                title: "Manage snapshot",
                caption: "Keep a local Git export for this crawler's shareable data.",
                isOn: self.$app.shareEnabled)
                .onChange(of: self.app.shareEnabled) { self.save() }
            if self.hasSnapshotRemote {
                CrawlBarSwitchRow(
                    title: "Publish after sync",
                    caption: "Push the snapshot after a scheduled or manual sync.",
                    isOn: self.$app.shareAfterRefresh)
                    .disabled(!self.app.shareEnabled)
                    .onChange(of: self.app.shareAfterRefresh) { self.save() }
                HStack(spacing: 8) {
                    if self.commandAvailable(self.app.preferredShareAction ?? "publish") {
                        Button {
                            self.runAction(self.app.preferredShareAction ?? "publish")
                        } label: {
                            Label("Publish Snapshot", systemImage: "arrow.up.circle")
                        }
                    }
                    if self.commandAvailable(self.app.preferredUpdateAction ?? "update") {
                        Button {
                            self.runAction(self.app.preferredUpdateAction ?? "update")
                        } label: {
                            Label("Pull Updates", systemImage: "arrow.down.circle")
                        }
                    }
                }
                .disabled(!self.app.shareEnabled || self.runningAction != nil)
            }
            if self.hasSnapshotInfo {
                Divider()
                if let shareRepoPath = self.shareRepoPath {
                    CrawlBarFact(label: "Share Repo", value: shareRepoPath)
                }
                if let shareRemote = self.shareRemote {
                    CrawlBarFact(label: "Remote", value: shareRemote)
                }
                if let shareBranch = self.shareBranch {
                    CrawlBarFact(label: "Branch", value: shareBranch)
                }
            }
        }
    }

    @ViewBuilder
    private var cloudArchiveSettings: some View {
        if self.commandAvailable("cloud-publish") || self.commandAvailable("remote-status") || self.commandAvailable("remote-archives") {
            CrawlBarPanel(title: "Cloudflare Archive") {
                CrawlBarOptionLabel(
                    title: "Remote SQLite archive",
                    caption: "Publish a compressed SQLite bundle and use the configured Worker archive for live reads.")
                HStack(spacing: 8) {
                    if self.commandAvailable("cloud-publish") {
                        Button {
                            self.runAction("cloud-publish")
                        } label: {
                            Label("Publish Cloud", systemImage: "icloud.and.arrow.up")
                        }
                    }
                    if self.commandAvailable("remote-status") {
                        Button {
                            self.runAction("remote-status")
                        } label: {
                            Label("Remote Status", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    if self.commandAvailable("remote-archives") {
                        Button {
                            self.runAction("remote-archives")
                        } label: {
                            Label("Archives", systemImage: "tray.full")
                        }
                    }
                }
                .disabled(self.runningAction != nil)
                if let remote = self.status?.remote {
                    Divider()
                    if let endpoint = remote.endpoint?.nilIfBlank {
                        CrawlBarFact(label: "Endpoint", value: endpoint)
                    }
                    if let archive = remote.archive?.nilIfBlank {
                        CrawlBarFact(label: "Archive", value: archive)
                    }
                    if let sqliteBundle = self.status?.sqliteBundle {
                        CrawlBarFact(label: "Bundle", value: self.bundleSummary(sqliteBundle))
                    }
                }
            }
        }
    }

    private var paths: some View {
        CrawlBarPanel(title: "Paths") {
            CrawlBarControlRow(
                title: "Binary path override",
                caption: "Leave empty to resolve the CLI from PATH.")
            {
                TextField("Optional", text: self.optionalText(\.binaryPath))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(self.save)
            }
            CrawlBarControlRow(
                title: "Config path override",
                caption: "Leave empty to use the crawler default.")
            {
                TextField("Optional", text: self.optionalText(\.configPath))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(self.save)
            }
            CrawlBarFact(label: "Default Config", value: self.manifest?.paths.defaultConfig ?? "None")
            CrawlBarFact(label: "Default Database", value: self.status?.databasePath ?? self.manifest?.paths.defaultDatabase ?? "Unknown")
            CrawlBarFact(label: "Logs", value: self.manifest?.paths.defaultLogs ?? "Unknown")
        }
    }

    @ViewBuilder
    private var configuration: some View {
        if self.manifest?.availability == .comingSoon {
            CrawlBarPanel(title: "Coming Soon") {
                CrawlBarFact(label: "CLI", value: self.manifest?.binary.name ?? self.app.id.rawValue)
                CrawlBarFact(label: "Config", value: self.manifest?.paths.defaultConfig ?? "Not declared")
            }
        } else if let manifest = self.manifest, !manifest.configOptions.isEmpty {
            ForEach(self.configSections(for: manifest)) { section in
                CrawlBarPanel(title: section.title, caption: section.caption) {
                    ForEach(section.options) { option in
                        CrawlBarConfigOptionField(
                            option: option,
                            value: self.configValueBinding(for: option),
                            disabledReason: self.configDisabledReason(for: option))
                    }
                }
            }
        }
    }

    private var privacy: some View {
        CrawlBarPanel(title: "Privacy") {
            CrawlBarFact(
                label: "Private Messages",
                value: self.manifest?.privacy.containsPrivateMessages == true ? "Possible local data" : "Not declared")
            CrawlBarFact(label: "Local-only scopes", value: self.manifest?.privacy.localOnlyScopes.joined(separator: ", ").nilIfBlank ?? "None")
            CrawlBarFact(label: "Action logs", value: CrawlActionLogStore.defaultDirectory().path)
        }
    }

    private var primaryIssue: String? {
        if let error = self.status?.errors.first?.nilIfBlank,
           !self.issueDuplicatesStatusSummary(error)
        {
            return error
        }
        if let warning = self.status?.warnings.first?.nilIfBlank,
           !self.issueDuplicatesStatusSummary(warning)
        {
            return warning
        }
        guard let latestResult, !latestResult.succeeded else { return nil }
        return latestResult.userFacingRunMessage ?? "\(Self.actionTitle(latestResult.action)) failed with exit \(latestResult.exitCode)"
    }

    private func issueDuplicatesStatusSummary(_ issue: String) -> Bool {
        guard let summary = self.status?.summary.nilIfBlank else { return false }
        return summary.localizedCaseInsensitiveContains(issue)
    }

    private var issueState: CrawlAppState {
        self.status?.isRecoverableGraincrawlSourceFailure == true ? .stale : .error
    }

    private var issueColor: Color {
        self.issueState == .stale ? .yellow : .red
    }

    private var refreshSourceSummary: String {
        if self.app.id == BuiltInCrawlApps.gitcrawlID {
            return "GitHub API (remote)"
        }
        if self.app.id == BuiltInCrawlApps.graincrawlID {
            switch self.app.configValues["preferred_source"]?.nilIfBlank ?? "private-api" {
            case "desktop-cache":
                return "Granola desktop cache"
            case "private-api":
                return "Granola private API (remote)"
            default:
                return self.app.configValues["preferred_source"] ?? "Granola source"
            }
        }
        if self.manifest?.capabilities.contains(.desktopCache) == true {
            return "Desktop cache (local)"
        }
        if self.manifest?.capabilities.contains(.refresh) == true {
            return "Crawler CLI"
        }
        return "Not available"
    }

    private var archiveSourceSummary: String {
        if let remoteStore = self.remoteStoreSummary {
            return remoteStore.shortName
        }
        if let database = self.primaryDatabase ?? self.status?.databases.first {
            return database.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? database.label
        }
        if let databasePath = self.status?.databasePath ?? self.manifest?.paths.defaultDatabase {
            return URL(fileURLWithPath: databasePath).lastPathComponent
        }
        return "Unknown"
    }

    private var snapshotSummary: String {
        guard self.app.shareEnabled else { return "Off" }
        guard let share = self.status?.share else {
            return self.shareRepoPath == nil ? "Configured, not reported" : "Local snapshot"
        }
        let location = share.remote?.nilIfBlank ?? share.repoPath?.nilIfBlank ?? "Local snapshot"
        if let branch = share.branch?.nilIfBlank {
            return "\(location) · \(branch)"
        }
        return location
    }

    private var hasSnapshotRemote: Bool {
        self.app.shareEnabled && self.shareRemote != nil
    }

    private var hasSnapshotInfo: Bool {
        self.app.shareEnabled && (self.shareRepoPath != nil || self.shareRemote != nil || self.shareBranch != nil)
    }

    private var shareRepoPath: String? {
        self.status?.share?.repoPath?.nilIfBlank ?? self.manifest?.paths.defaultShare?.nilIfBlank
    }

    private var shareRemote: String? {
        self.status?.share?.remote?.nilIfBlank
    }

    private var shareBranch: String? {
        self.status?.share?.branch?.nilIfBlank
    }

    private var configSourceSummary: String {
        if let configPath = self.status?.configPath ?? self.app.configPath ?? self.manifest?.paths.defaultConfig {
            return URL(fileURLWithPath: configPath).lastPathComponent
        }
        return "None"
    }

    private static func actionTitle(_ action: String) -> String {
        switch action {
        case "refresh":
            "Sync"
        case "doctor":
            "Doctor"
        case "unlock":
            "Unlock"
        case "publish":
            "Publish"
        case "cloud-publish":
            "Cloud Publish"
        case "remote-status":
            "Remote Status"
        case "remote-archives":
            "Remote Archives"
        case "update":
            "Update"
        case "desktop-cache-import":
            "Desktop Import"
        default:
            action
        }
    }

    private var effectiveState: CrawlAppState {
        if self.isComingSoon { return .disabled }
        if !self.app.enabled { return .disabled }
        if self.installation?.binaryPath == nil { return .needsConfig }
        let state = self.status?.state ?? .unknown
        if self.status?.isRecoverableGraincrawlSourceFailure == true {
            return .stale
        }
        return state
    }

    private var statusFallback: String {
        switch self.effectiveState {
        case .disabled where self.isComingSoon:
            "Coming soon"
        case .needsConfig:
            "\(self.manifest?.binary.name ?? self.app.id.rawValue) is not on PATH"
        case .disabled:
            "Disabled in CrawlBar"
        default:
            "Waiting for status"
        }
    }

    private var databaseSummary: String {
        guard let status else { return "Unknown" }
        if let remoteStore = self.remoteStoreSummary {
            return remoteStore.databaseSummary
        }
        if self.app.id == BuiltInCrawlApps.gitcrawlID {
            return self.summaryText(label: "GitHub archives", bytes: self.totalDatabaseBytes)
        }
        if status.databases.count > 1 {
            return self.summaryText(label: "\(status.databases.count) databases", bytes: self.totalDatabaseBytes)
        }
        if let primaryDatabase = self.primaryDatabase ?? status.databases.first {
            let size = primaryDatabase.bytes ?? status.databaseBytes
            return self.summaryText(label: primaryDatabase.label, bytes: size)
        }
        return status.databasePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown"
    }

    private var binarySummary: String {
        if self.isComingSoon { return "Coming soon" }
        return self.installation?.binaryPath == nil ? "Missing" : "Found"
    }

    private var lastSyncSummary: String {
        guard let date = self.lastSyncDate else { return "Never" }
        return "Synced \(CrawlBarDateText.relative(date))"
    }

    private var lastSyncDate: Date? {
        if let lastSyncAt = self.status?.lastSyncAt {
            return lastSyncAt
        }
        if let modifiedAt = self.primaryDatabase?.modifiedAt {
            return modifiedAt
        }
        return self.status?.databases.compactMap(\.modifiedAt).max()
    }

    private var primaryDatabase: CrawlDatabaseResource? {
        self.status?.databases.first(where: { $0.isPrimary })
    }

    private var totalDatabaseBytes: Int? {
        guard let status else { return nil }
        let total = status.databases.compactMap(\.bytes).reduce(0, +)
        if total > 0 { return total }
        return status.databaseBytes
    }

    private var overviewCounts: [CrawlCount] {
        if let primaryCounts = self.primaryDatabase?.counts, !primaryCounts.isEmpty {
            return primaryCounts
        }
        let databaseCounts = self.totalCountsAcrossDatabases()
        if !databaseCounts.isEmpty {
            return databaseCounts
        }
        return self.status?.counts ?? []
    }

    private var overviewDataScope: String {
        if let remoteStore = self.remoteStoreSummary {
            return remoteStore.dataScope
        }
        if self.primaryDatabase?.counts.isEmpty == false {
            return "Active database"
        }
        if let count = self.status?.databases.count, count > 1, !self.totalCountsAcrossDatabases().isEmpty {
            return "Total across \(count) databases"
        }
        return "Connected database"
    }

    private func totalCountsAcrossDatabases() -> [CrawlCount] {
        let counts = self.status?.databases.flatMap(\.counts) ?? []
        guard !counts.isEmpty else { return [] }
        var labels: [String: String] = [:]
        var values: [String: Int] = [:]
        for count in counts {
            labels[count.id] = labels[count.id] ?? count.label
            values[count.id, default: 0] += count.value
        }
        return values.keys.sorted().map { id in
            CrawlCount(id: id, label: labels[id] ?? id, value: values[id] ?? 0)
        }
    }

    private func summaryText(label: String, bytes: Int?) -> String {
        [
            label,
            bytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) },
        ].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
    }

    private func bundleSummary(_ bundle: CrawlSQLiteBundleStatus) -> String {
        [
            bundle.format?.nilIfBlank,
            bundle.compression?.nilIfBlank,
            bundle.compressedBytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) },
            bundle.partCount.map { "\($0) part\($0 == 1 ? "" : "s")" },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var isComingSoon: Bool {
        self.manifest?.availability == .comingSoon
    }

    private var isMissingBinary: Bool {
        self.manifest?.availability == .available && self.installation?.binaryPath == nil
    }

    private var usesRemoteStore: Bool {
        self.remoteStoreSummary != nil
    }

    private var remoteStoreSummary: CrawlBarRemoteStoreSummary? {
        if let remote = self.status?.remote, remote.enabled {
            let database = self.status?.databases.first(where: { $0.endpoint != nil || $0.archive != nil })
            let endpoint = remote.endpoint?.nilIfBlank ?? database?.endpoint?.nilIfBlank ?? "Cloudflare remote"
            let archive = remote.archive?.nilIfBlank ?? database?.archive?.nilIfBlank
            return CrawlBarRemoteStoreSummary(
                remote: endpoint,
                archive: archive,
                kind: .cloudflare,
                sqliteBundle: self.status?.sqliteBundle,
                sqliteObject: self.status?.sqliteObject,
                lastIngestAt: remote.lastIngestAt ?? remote.lastSyncAt)
        }
        if self.status?.share?.enabled == true, let remote = self.status?.share?.remote?.nilIfBlank {
            return CrawlBarRemoteStoreSummary(
                remote: remote,
                repoPath: self.status?.share?.repoPath?.nilIfBlank,
                branch: self.status?.share?.branch?.nilIfBlank,
                kind: .gitSnapshot)
        }
        guard self.app.id == BuiltInCrawlApps.gitcrawlID else { return nil }
        var paths = self.status?.databases.compactMap(\.path) ?? []
        if let databasePath = self.status?.databasePath {
            paths.append(databasePath)
        }
        guard let storePath = paths.first(where: { $0.contains("/gitcrawl-store/") || $0.contains("/gitcrawl-store-remote/") }) else {
            return nil
        }
        let repoPath = Self.repoPath(containing: "/data/", in: storePath)
        return CrawlBarRemoteStoreSummary(
            remote: "https://github.com/openclaw/gitcrawl-store.git",
            repoPath: repoPath,
            branch: nil,
            kind: .gitSnapshot)
    }

    private var usesGlobalRefreshBinding: Binding<Bool> {
        Binding(
            get: { self.app.refreshFrequency == nil },
            set: {
                self.app.refreshFrequency = $0 ? nil : self.globalRefreshFrequency
                self.save()
            })
    }

    private var refreshFrequencyBinding: Binding<RefreshFrequency> {
        Binding(
            get: { self.app.refreshFrequency ?? self.globalRefreshFrequency },
            set: {
                self.app.refreshFrequency = $0
                self.save()
            })
    }

    private func commandAvailable(_ action: String) -> Bool {
        guard self.manifest?.availability == .available else { return false }
        return self.manifest?.commands[action] != nil && self.installation?.binaryPath != nil && self.app.enabled
    }

    private var nativeAppAvailable: Bool {
        guard let bundleIdentifier = self.manifest?.branding.bundleIdentifier?.nilIfBlank else { return false }
        return CrawlBarNativeAppLocator.url(for: bundleIdentifier) != nil
    }

    private func openNativeApp() {
        guard let bundleIdentifier = self.manifest?.branding.bundleIdentifier?.nilIfBlank,
              let url = CrawlBarNativeAppLocator.url(for: bundleIdentifier)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func optionalText(_ keyPath: WritableKeyPath<CrawlBarAppConfig, String?>) -> Binding<String> {
        Binding(
            get: { self.app[keyPath: keyPath] ?? "" },
            set: {
                self.app[keyPath: keyPath] = $0.nilIfBlank
                self.saveDebounced()
            })
    }

    private func configValueBinding(for option: CrawlAppManifest.ConfigOption) -> Binding<String> {
        Binding(
            get: { self.app.configValues[option.id] ?? option.defaultValue ?? "" },
            set: {
                let value = $0.nilIfBlank
                self.app.configValues[option.id] = value
                self.configValueChanged(option, value)
            })
    }

    private func configDisabledReason(for option: CrawlAppManifest.ConfigOption) -> String? {
        guard self.usesRemoteStore else { return nil }
        let optionText = [
            option.id,
            option.configKey,
            option.envVar,
        ].compactMap { $0?.lowercased() }.joined(separator: " ")
        guard optionText.contains("openai") || optionText.contains("embedding") else { return nil }
        return "Disabled while this crawler is using a remote store."
    }

    private static func repoPath(containing marker: String, in path: String) -> String? {
        guard let range = path.range(of: marker) else { return nil }
        return String(path[..<range.lowerBound])
    }

    private func configSections(for manifest: CrawlAppManifest) -> [CrawlBarConfigSection] {
        var optionsByID: [String: CrawlAppManifest.ConfigOption] = [:]
        for option in manifest.configOptions where optionsByID[option.id] == nil {
            optionsByID[option.id] = option
        }
        let sections = manifest.configSections.isEmpty
            ? [CrawlBarConfigSection(id: "config", title: "Configuration", optionIDs: manifest.configOptions.map(\.id))]
            : manifest.configSections.map {
                CrawlBarConfigSection(
                    id: $0.id,
                    title: $0.title,
                    caption: $0.caption,
                    optionIDs: $0.optionIDs)
            }

        let usedIDs = Set(sections.flatMap(\.optionIDs))
        let resolved = sections.compactMap { section -> CrawlBarConfigSection? in
            let options = section.optionIDs.compactMap { optionsByID[$0] }
            guard !options.isEmpty else { return nil }
            return section.resolved(options: options)
        }
        let extraOptions = manifest.configOptions.filter { !usedIDs.contains($0.id) }
        if extraOptions.isEmpty {
            return resolved
        }
        return resolved + [CrawlBarConfigSection(id: "advanced", title: "Advanced", optionIDs: [], options: extraOptions)]
    }
}

private struct CrawlBarConfigSection: Identifiable {
    var id: String
    var title: String
    var caption: String?
    var optionIDs: [String]
    var options: [CrawlAppManifest.ConfigOption]

    init(
        id: String,
        title: String,
        caption: String? = nil,
        optionIDs: [String],
        options: [CrawlAppManifest.ConfigOption] = [])
    {
        self.id = id
        self.title = title
        self.caption = caption
        self.optionIDs = optionIDs
        self.options = options
    }

    func resolved(options: [CrawlAppManifest.ConfigOption]) -> CrawlBarConfigSection {
        CrawlBarConfigSection(
            id: self.id,
            title: self.title,
            caption: self.caption,
            optionIDs: self.optionIDs,
            options: options)
    }
}

struct CrawlBarDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.title)
                .font(.headline.weight(.semibold))
            VStack(alignment: .leading, spacing: 14) {
                self.content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CrawlBarPanel<Content: View>: View {
    var title: String?
    var caption: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                self.content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.055))
            }
        }
    }
}

struct CrawlBarStatusDot: View {
    let state: CrawlAppState

    var body: some View {
        Circle()
            .fill(self.color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(CrawlBarStatusLabel.text(for: self.state))
    }

    private var color: Color {
        switch self.state {
        case .current:
            .green
        case .stale, .unknown:
            .yellow
        case .syncing:
            .blue
        case .needsConfig, .needsAuth, .error:
            .red
        case .disabled:
            .gray
        }
    }
}

struct CrawlBarStatusPill: View {
    let state: CrawlAppState

    var body: some View {
        HStack(spacing: 5) {
            CrawlBarStatusDot(state: self.state)
            Text(CrawlBarStatusLabel.text(for: self.state))
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct CrawlBarFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(self.value)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CrawlBarIssueBanner: View {
    let message: String
    let state: CrawlAppState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(self.color)
            Text(self.message)
                .font(.caption)
                .foregroundStyle(self.color)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var color: Color {
        self.state == .stale ? .yellow : .red
    }
}

struct CrawlBarControlRow<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder var content: Content

    init(title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .font(.callout)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            self.content
        }
    }
}

struct CrawlBarSwitchRow: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CrawlBarOptionLabel(title: self.title, caption: self.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(self.title, isOn: self.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

struct CrawlBarOptionLabel: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.title)
                .font(.callout)
            Text(self.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CrawlBarMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(self.label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(self.value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CrawlBarRemoteStoreSummary {
    enum Kind {
        case gitSnapshot
        case cloudflare
    }

    var remote: String
    var archive: String? = nil
    var repoPath: String? = nil
    var branch: String? = nil
    var kind: Kind
    var sqliteBundle: CrawlSQLiteBundleStatus? = nil
    var sqliteObject: CrawlSQLiteObjectStatus? = nil
    var lastIngestAt: Date? = nil

    var title: String {
        switch self.kind {
        case .cloudflare:
            "Cloudflare Archive"
        case .gitSnapshot:
            "Remote Store"
        }
    }

    var shortName: String {
        if self.kind == .cloudflare {
            return self.archive?.nilIfBlank ?? "Cloudflare archive"
        }
        let trimmed = self.remote
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .nilIfBlank
        return trimmed ?? "Remote store"
    }

    var dataScope: String {
        switch self.kind {
        case .cloudflare:
            "Cloudflare remote"
        case .gitSnapshot:
            "Remote store"
        }
    }

    var databaseSummary: String {
        guard self.kind == .cloudflare else { return self.shortName }
        let pieces = [
            self.shortName,
            self.sqliteBundle?.compressedBytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) },
            self.sqliteBundle?.compression?.nilIfBlank,
        ].compactMap { $0 }
        return pieces.isEmpty ? "Cloudflare archive" : pieces.joined(separator: " · ")
    }

    var bundle: String? {
        guard let sqliteBundle else { return nil }
        return [
            sqliteBundle.format?.nilIfBlank,
            sqliteBundle.compression?.nilIfBlank,
        ].compactMap { $0 }.joined(separator: " · ").nilIfBlank
    }

    var compressed: String? {
        let values = [
            sqliteBundle?.compressedBytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) },
            sqliteBundle?.rawBytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) + " raw" },
            sqliteObject?.bytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) + " object" },
        ].compactMap { $0?.nilIfBlank }
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }

    var parts: String? {
        sqliteBundle?.partCount.map { "\($0)" }
    }

    var lastIngest: String? {
        guard let lastIngestAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastIngestAt, relativeTo: Date())
    }
}

struct CrawlBarDatabaseRow: View {
    let database: CrawlDatabaseResource

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: self.iconName)
                .font(.body)
                .foregroundStyle(self.database.isPrimary ? .blue : .secondary)
                .frame(width: 18, height: 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(self.database.label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if self.database.isPrimary {
                        Text("Primary")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(self.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if !self.database.counts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(self.database.counts.prefix(3)) { count in
                            Text("\(count.value) \(count.label.lowercased())")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let bytes = self.database.bytes {
                    Text(CrawlBarFileSizeText.string(fromByteCount: Int64(bytes)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let modifiedAt = self.database.modifiedAt {
                    Text(CrawlBarDateText.relative(modifiedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        let pieces = [
            self.database.role,
            self.database.path,
        ].compactMap { $0?.nilIfBlank }
        return pieces.isEmpty ? self.database.kind.rawValue : pieces.joined(separator: " · ")
    }

    private var iconName: String {
        switch self.database.kind {
        case .sqlite:
            "internaldrive"
        case .cache:
            "externaldrive.connected.to.line.below"
        case .logical:
            "square.stack.3d.up"
        case .remote, .d1, .cloudflareD1:
            "cloud"
        case .sqliteBundle:
            "archivebox"
        }
    }
}

struct CrawlBarConfigOptionField: View {
    let option: CrawlAppManifest.ConfigOption
    @Binding var value: String
    var disabledReason: String?

    var body: some View {
        CrawlBarControlRow(title: self.option.label, caption: self.caption) {
            self.control
        }
        .disabled(self.disabledReason != nil)
    }

    @ViewBuilder
    private var control: some View {
        switch self.option.kind {
        case .secret:
            HStack(spacing: 8) {
                SecureField(self.option.placeholder ?? "Value", text: self.$value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                Button {
                    self.value = ""
                } label: {
                    Image(systemName: "key.slash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear saved secret")
            }
        case .boolean:
            Toggle("", isOn: self.booleanBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        case .choice:
            Picker("Value", selection: self.$value) {
                ForEach(self.choices, id: \.self) { choice in
                    Text(choice).tag(choice)
                }
            }
            .labelsHidden()
            .frame(width: 220)
        case .string:
            TextField(self.option.placeholder ?? "Value", text: self.$value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
        case .number:
            TextField(self.option.placeholder ?? "0", text: self.$value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    private var caption: String? {
        [
            self.disabledReason?.nilIfBlank,
            self.option.help?.nilIfBlank,
            self.metadata,
        ].compactMap { $0 }.joined(separator: "\n").nilIfBlank
    }

    private var metadata: String? {
        [
            self.option.envVar?.nilIfBlank,
            self.option.configKey?.nilIfBlank,
        ].compactMap { $0 }.joined(separator: "   ").nilIfBlank
    }

    private var choices: [String] {
        var resolved = self.option.choices
        if let defaultValue = self.option.defaultValue?.nilIfBlank,
           !resolved.contains(defaultValue)
        {
            resolved.insert(defaultValue, at: 0)
        }
        if let currentValue = self.value.nilIfBlank,
           !resolved.contains(currentValue)
        {
            resolved.insert(currentValue, at: 0)
        }
        return resolved
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { ["1", "true", "yes", "on"].contains(self.value.lowercased()) },
            set: { self.value = $0 ? "true" : "false" })
    }
}

enum CrawlBarFrequencyLabel {
    static func text(for frequency: RefreshFrequency) -> String {
        switch frequency {
        case .manual:
            "Manual"
        case .fiveMinutes:
            "5 minutes"
        case .fifteenMinutes:
            "15 minutes"
        case .thirtyMinutes:
            "30 minutes"
        case .hourly:
            "Hourly"
        }
    }
}

enum CrawlBarStatusLabel {
    static func text(for state: CrawlAppState) -> String {
        switch state {
        case .current:
            "Current"
        case .stale:
            "Stale"
        case .syncing:
            "Syncing"
        case .needsConfig:
            "Needs Config"
        case .needsAuth:
            "Needs Auth"
        case .error:
            "Error"
        case .disabled:
            "Disabled"
        case .unknown:
            "Unknown"
        }
    }
}

@MainActor
enum CrawlBarDateText {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relative(_ date: Date) -> String {
        self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

enum CrawlBarFileSizeText {
    private static let formatter = CrawlBarLockedByteCountFormatter()

    static func string(fromByteCount byteCount: Int64) -> String {
        self.formatter.string(fromByteCount: byteCount)
    }
}

private final class CrawlBarLockedByteCountFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter
    }()

    func string(fromByteCount byteCount: Int64) -> String {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.formatter.string(fromByteCount: byteCount)
    }
}
