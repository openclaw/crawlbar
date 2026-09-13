import Foundation

public enum CrawlInstallerError: LocalizedError, Sendable {
    case installUnavailable(CrawlAppID)
    case brewUnavailable
    case unsupportedMethod(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .installUnavailable(appID):
            "\(appID.rawValue) does not declare an installer"
        case .brewUnavailable:
            "Homebrew is not available on PATH"
        case let .unsupportedMethod(method):
            "Unsupported install method: \(method)"
        case let .failed(message):
            message
        }
    }
}

public struct CrawlInstaller: Sendable {
    private let resolver: CrawlExecutableResolver
    private let redactor: CrawlCommandRedactor
    private let environment: [String: String]

    public init(
        resolver: CrawlExecutableResolver = CrawlExecutableResolver(),
        redactor: CrawlCommandRedactor = CrawlCommandRedactor(),
        environment: [String: String] = ProcessInfo.processInfo.environment)
    {
        self.resolver = resolver
        self.redactor = redactor
        self.environment = CrawlProcessEnvironment.normalized(environment)
    }

    public func install(_ installation: CrawlAppInstallation, timeoutSeconds: TimeInterval = 900) throws -> CrawlCommandResult {
        guard let install = installation.manifest.install else {
            throw CrawlInstallerError.installUnavailable(installation.id)
        }

        switch install.method {
        case .homebrew:
            guard let brewPath = self.resolver.resolve("brew") else {
                throw CrawlInstallerError.brewUnavailable
            }
            return try self.run(
                appID: installation.id,
                executablePath: brewPath,
                arguments: ["install", install.package],
                timeoutSeconds: timeoutSeconds)
        }
    }

    private func run(
        appID: CrawlAppID,
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval)
        throws -> CrawlCommandResult
    {
        let runner = CrawlCommandRunner(
            resolver: self.resolver,
            redactor: self.redactor,
            environment: self.environment)
        let result = try runner.runProcess(
            appID: appID,
            action: "install",
            executablePath: executablePath,
            arguments: arguments,
            environment: self.environment,
            maskedValues: [],
            timeoutSeconds: timeoutSeconds)
        if result.exitCode != 0 {
            throw CrawlInstallerError.failed(result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Install failed with exit \(result.exitCode)")
        }
        return result
    }
}
