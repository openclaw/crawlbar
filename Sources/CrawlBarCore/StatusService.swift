import Foundation

public struct CrawlStatusService: @unchecked Sendable {
    private let runner: CrawlCommandRunner
    private let mapper: CrawlStatusMapper

    public init(
        runner: CrawlCommandRunner = CrawlCommandRunner(),
        mapper: CrawlStatusMapper = CrawlStatusMapper())
    {
        self.runner = runner
        self.mapper = mapper
    }

    public func status(for installation: CrawlAppInstallation, timeoutSeconds: TimeInterval = 30) -> CrawlAppStatus {
        self.status(
            for: installation,
            configValues: installation.configValues,
            timeoutSeconds: timeoutSeconds)
    }

    package func status(
        for installation: CrawlAppInstallation,
        configValues: [String: String],
        timeoutSeconds: TimeInterval = 30)
        -> CrawlAppStatus
    {
        if let status = self.immediateStatus(for: installation) {
            return status
        }
        do {
            let status = try self.commandStatus(
                for: installation,
                configValues: configValues,
                action: "status",
                timeoutSeconds: timeoutSeconds)
            guard installation.id == BuiltInCrawlApps.gogcliID, status.state != .current else {
                return status
            }
            return try self.commandStatus(
                for: installation,
                configValues: configValues,
                action: "doctor",
                timeoutSeconds: timeoutSeconds)
        } catch CrawlCommandRunnerError.timedOut {
            return CrawlAppStatus(
                appID: installation.id,
                state: .unknown,
                summary: "Status check is slow; run Doctor for a full check")
        } catch CrawlCommandRunnerError.missingRequiredConfig {
            return CrawlAppStatus(appID: installation.id, state: .needsConfig, summary: "Remote settings are incomplete")
        } catch {
            return CrawlAppStatus(appID: installation.id, state: .error, summary: error.localizedDescription, errors: [error.localizedDescription])
        }
    }

    public func immediateStatus(for installation: CrawlAppInstallation) -> CrawlAppStatus? {
        guard installation.manifest.availability == .available else {
            return CrawlAppStatus(appID: installation.id, state: .disabled, summary: "Coming soon")
        }
        guard installation.enabled else {
            return CrawlAppStatus(appID: installation.id, state: .disabled, summary: "Disabled in CrawlBar config")
        }
        guard installation.binaryPath != nil else {
            return CrawlAppStatus(appID: installation.id, state: .needsConfig, summary: "\(installation.manifest.binary.name) is not on PATH")
        }
        return GitcrawlStatusSnapshot.status(for: installation)
    }

    private func commandStatus(
        for installation: CrawlAppInstallation,
        configValues: [String: String],
        action: String,
        timeoutSeconds: TimeInterval)
        throws -> CrawlAppStatus
    {
        let result = try self.runner.run(
            installation: installation,
            configValues: configValues,
            action: action,
            timeoutSeconds: timeoutSeconds)
        return self.mapper.status(
            from: result,
            manifest: installation.manifest,
            staleAfterSeconds: installation.staleAfterSeconds)
    }
}
