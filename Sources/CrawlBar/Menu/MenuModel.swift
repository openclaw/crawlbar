import CrawlBarCore
import Foundation

private struct CrawlActionStatusUpdate: Sendable {
    let status: CrawlAppStatus
    let actionFailure: CrawlAppStatus?
}

@MainActor
final class CrawlBarMenuModel: NSObject {
    private let registry = CrawlAppRegistry()
    private let runner: CrawlCommandRunner
    private let statusService: CrawlStatusService
    private let logStore = CrawlActionLogStore()

    var installations: [CrawlAppInstallation] = []
    var statuses: [CrawlAppID: CrawlAppStatus] = [:]
    var isRefreshing = false
    var refreshFrequency: RefreshFrequency = .fifteenMinutes
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var appConfigs: [CrawlAppID: CrawlBarAppConfig] = [:]
    private var lastAutoSyncByAppID: [CrawlAppID: Date] = [:]

    override init() {
        let runner = CrawlCommandRunner()
        self.runner = runner
        self.statusService = CrawlStatusService(runner: runner)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(Self.statusesDidChange(_:)),
            name: .crawlBarStatusesDidChange,
            object: nil)
        self.reloadInstallations()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var visibleInstallations: [CrawlAppInstallation] {
        self.installations.filter { installation in
            guard installation.manifest.availability == .available else { return false }
            return self.appConfigs[installation.id]?.showInMenuBar ?? true
        }
    }

    var statusTargetInstallations: [CrawlAppInstallation] {
        self.installations.filter { installation in
            guard installation.manifest.availability == .available else { return false }
            return self.appConfigs[installation.id]?.enabled ?? installation.enabled
        }
    }

    func appConfig(for id: CrawlAppID) -> CrawlBarAppConfig? {
        self.appConfigs[id]
    }

    func reloadInstallations() {
        if let config = try? self.registry.loadConfig() {
            self.refreshFrequency = config.refreshFrequency
            self.appConfigs = Dictionary(uniqueKeysWithValues: config.apps.map { ($0.id, $0) })
        } else {
            CrawlBarLog.config.error("Failed to load CrawlBar config")
        }
        self.installations = (try? self.registry.installations(includeDisabled: true)) ?? []
    }

    func refreshAll(onComplete: @escaping @MainActor () -> Void) {
        self.refreshTask?.cancel()
        let generation = UUID()
        self.refreshGeneration = generation
        self.isRefreshing = true
        let appConfigs = self.appConfigs
        let registry = self.registry
        let statusService = self.statusService
        self.refreshTask = Task.detached {
            let installations = (try? registry.installationsForStatus(includeDisabled: true)) ?? []
            let statusInstallations = installations.filter { installation in
                guard installation.manifest.availability == .available else { return false }
                return appConfigs[installation.id]?.enabled ?? installation.enabled
            }
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                self.installations = installations
                onComplete()
            }
            let partitioned = Self.partitionStatuses(installations: statusInstallations, statusService: statusService)
            if !partitioned.immediate.isEmpty {
                await MainActor.run {
                    guard self.refreshGeneration == generation else { return }
                    for status in partitioned.immediate {
                        self.statuses[status.appID] = status
                    }
                    CrawlBarStateBroadcast.statusesDidChange(Dictionary(uniqueKeysWithValues: partitioned.immediate.map { ($0.appID, $0) }))
                    onComplete()
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
                        onComplete()
                    }
                }
            }
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                self.isRefreshing = false
                self.refreshTask = nil
                onComplete()
            }
        }
    }

    func runDueAutoSync(onComplete: @escaping @MainActor () -> Void) {
        guard !self.isRefreshing else { return }
        self.reloadInstallations()
        let now = Date()
        let dueInstallations = self.installations.filter { installation in
            guard let config = self.appConfigs[installation.id], config.enabled, config.autoRefreshEnabled else { return false }
            guard installation.enabled, installation.binaryPath != nil else { return false }
            guard let seconds = (config.refreshFrequency ?? self.refreshFrequency).seconds else { return false }
            let last = self.lastAutoSyncByAppID[installation.id] ?? .distantPast
            return now.timeIntervalSince(last) >= seconds
        }
        guard !dueInstallations.isEmpty else { return }

        self.isRefreshing = true
        let configs = self.appConfigs
        let registry = self.registry
        let runner = self.runner
        let statusService = self.statusService
        let logStore = self.logStore
        Task.detached {
            let updates = dueInstallations.map { installation -> CrawlActionStatusUpdate in
                let actionInstallation = (try? registry.installation(for: installation.id, includeSecrets: true)) ?? installation
                let statusInstallation = (try? registry.installationForStatus(for: installation.id)) ?? installation

                func failureUpdate(_ failure: CrawlAppStatus) -> CrawlActionStatusUpdate {
                    CrawlActionStatusUpdate(
                        status: statusService.status(for: statusInstallation, timeoutSeconds: 5),
                        actionFailure: failure)
                }

                if let config = configs[installation.id] {
                    let refreshAction = config.preferredRefreshAction ?? "refresh"
                    do {
                        CrawlBarLog.actions.notice("Running scheduled \(refreshAction, privacy: .public) for \(installation.id.rawValue, privacy: .public)")
                        let result = try runner.run(installation: actionInstallation, action: refreshAction, timeoutSeconds: 600)
                        _ = try? logStore.save(result)
                        if !result.succeeded {
                            CrawlBarLog.actions.error(
                                "Scheduled \(refreshAction, privacy: .public) for \(installation.id.rawValue, privacy: .public) failed with exit \(result.exitCode)")
                            return failureUpdate(Self.actionFailureStatus(result))
                        }
                    } catch {
                        CrawlBarLog.actions.error(
                            "Scheduled \(refreshAction, privacy: .public) for \(installation.id.rawValue, privacy: .public) threw: \(error.localizedDescription, privacy: .public)")
                        return failureUpdate(Self.actionFailureStatus(
                            appID: installation.id,
                            action: refreshAction,
                            message: error.localizedDescription))
                    }
                    if config.shareEnabled, config.shareAfterRefresh {
                        let shareAction = config.preferredShareAction ?? "publish"
                        do {
                            CrawlBarLog.actions.notice("Running scheduled \(shareAction, privacy: .public) for \(installation.id.rawValue, privacy: .public)")
                            let result = try runner.run(installation: actionInstallation, action: shareAction, timeoutSeconds: 600)
                            _ = try? logStore.save(result)
                            if !result.succeeded {
                                CrawlBarLog.actions.error(
                                    "Scheduled \(shareAction, privacy: .public) for \(installation.id.rawValue, privacy: .public) failed with exit \(result.exitCode)")
                                return failureUpdate(Self.actionFailureStatus(result))
                            }
                        } catch {
                            CrawlBarLog.actions.error(
                                "Scheduled \(shareAction, privacy: .public) for \(installation.id.rawValue, privacy: .public) threw: \(error.localizedDescription, privacy: .public)")
                            return failureUpdate(Self.actionFailureStatus(
                                appID: installation.id,
                                action: shareAction,
                                message: error.localizedDescription))
                        }
                    }
                }
                return CrawlActionStatusUpdate(
                    status: statusService.status(for: statusInstallation, timeoutSeconds: 5),
                    actionFailure: nil)
            }
            await MainActor.run {
                var changedStatuses: [CrawlAppID: CrawlAppStatus] = [:]
                for update in updates {
                    let status = update.actionFailure.map {
                        Self.actionFailureStatus($0, refreshedStatus: update.status, currentStatus: self.statuses[$0.appID])
                    } ?? update.status
                    self.statuses[status.appID] = status
                    changedStatuses[status.appID] = status
                    if update.actionFailure == nil, status.state != .error {
                        self.lastAutoSyncByAppID[status.appID] = now
                    }
                }
                CrawlBarStateBroadcast.statusesDidChange(changedStatuses)
                self.isRefreshing = false
                onComplete()
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
}
