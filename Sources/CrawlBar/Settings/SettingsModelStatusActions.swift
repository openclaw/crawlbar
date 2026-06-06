import CrawlBarCore
import Foundation

extension CrawlBarSettingsModel {
    func refreshAll() {
        self.loadRecentResultsAsync()
        self.refreshTask?.cancel()
        let generation = UUID()
        self.refreshGeneration = generation
        self.isRefreshing = true
        let appsForStatus = self.apps
        let registry = self.registry
        let statusService = self.statusService
        self.refreshTask = Task.detached {
            let installations = (try? registry.installationsForStatus(includeDisabled: true)) ?? []
            let appConfigsByID = Dictionary(uniqueKeysWithValues: appsForStatus.map { ($0.id, $0) })
            let statusInstallations = CrawlBarCrawlerClassifier.statusInstallations(
                installations,
                appConfigsByID: appConfigsByID)
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                let installationsByID = Dictionary(uniqueKeysWithValues: installations.map { ($0.id, $0) })
                self.installations = installationsByID
                self.apps = Self.sortedAppConfigs(self.apps, installationsByID: installationsByID)
            }
            let partitioned = Self.partitionStatuses(installations: statusInstallations, statusService: statusService)
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

    func loadRecentResults() {
        self.recentResultsGeneration = UUID()
        self.recentResults = Self.recentResults(logStore: self.logStore)
    }

    func loadRecentResultsAsync() {
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

    func mergeStatuses(_ incoming: [CrawlAppID: CrawlAppStatus]) {
        for (appID, status) in incoming {
            self.statuses[appID] = status
        }
    }

    @objc func statusesDidChange(_ notification: Notification) {
        guard let statuses = CrawlBarStateBroadcast.statuses(from: notification) else { return }
        self.mergeStatuses(statuses)
    }

    nonisolated static func partitionStatuses(
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

    nonisolated static func actionTitle(_ action: String) -> String {
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

    nonisolated static func actionFailureStatus(_ result: CrawlCommandResult) -> CrawlAppStatus {
        let fallback = "\(result.action) failed with exit \(result.exitCode)"
        return CrawlAppStatus.commandFailure(
            appID: result.appID,
            action: result.action,
            message: result.stderr.nilIfBlank ?? result.stdout.nilIfBlank,
            fallback: fallback)
    }

    nonisolated static func actionFailureStatus(appID: CrawlAppID, action: String, message: String) -> CrawlAppStatus {
        CrawlAppStatus.commandFailure(
            appID: appID,
            action: action,
            message: message,
            fallback: "\(action) failed")
    }

    nonisolated static func actionFailureStatus(
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
