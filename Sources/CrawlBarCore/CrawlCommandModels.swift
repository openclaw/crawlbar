import Foundation

public struct CrawlAppInstallation: Codable, Equatable, Sendable, Identifiable {
    public var manifest: CrawlAppManifest
    public var binaryPath: String?
    public var configPathOverride: String?
    public var configValues: [String: String]
    public var staleAfterSeconds: Int?
    public var enabled: Bool

    public var id: CrawlAppID {
        self.manifest.id
    }

    public init(
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

public enum CrawlActionID: String, Codable, Hashable, Sendable {
    case status
    case doctor
    case refresh
    case publish
    case update
    case desktopCacheImport = "desktop-cache-import"
    case exportMarkdown = "export-md"
}

public struct CrawlCommandResult: Codable, Equatable, Sendable {
    public var appID: CrawlAppID
    public var action: String
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var startedAt: Date
    public var finishedAt: Date

    public var succeeded: Bool {
        self.exitCode == 0
    }

    public init(
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

public extension CrawlCommandResult {
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
