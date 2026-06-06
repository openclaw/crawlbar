import AppKit
import CrawlBarCore
import Foundation

extension CrawlBarSettingsModel {
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

    nonisolated static func installBundledCLI() throws -> String {
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

    nonisolated static func cliSourceCandidates() -> [URL] {
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
