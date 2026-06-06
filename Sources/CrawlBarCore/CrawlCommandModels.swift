import Foundation

package struct CrawlAppInstallation: Codable, Equatable, Sendable, Identifiable {
    package var manifest: CrawlAppManifest
    package var binaryPath: String?
    package var configPathOverride: String?
    package var configValues: [String: String]
    package var staleAfterSeconds: Int?
    package var enabled: Bool

    package var id: CrawlAppID {
        self.manifest.id
    }

    package init(
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

package struct CrawlCommandResult: Codable, Equatable, Sendable {
    package var appID: CrawlAppID
    package var action: String
    package var exitCode: Int32
    package var stdout: String
    package var stderr: String
    package var startedAt: Date
    package var finishedAt: Date

    package var succeeded: Bool {
        self.exitCode == 0
    }

    package init(
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

package extension CrawlCommandResult {
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
