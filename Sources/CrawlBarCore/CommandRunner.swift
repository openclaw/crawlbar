import Foundation

public struct CrawlCommandRunner: @unchecked Sendable {
    static let timeoutTerminationGrace: DispatchTimeInterval = .milliseconds(500)

    let resolver: CrawlExecutableResolver
    let redactor: CrawlCommandRedactor
    let fileManager: FileManager
    let environment: [String: String]

    public init(
        resolver: CrawlExecutableResolver = CrawlExecutableResolver(),
        redactor: CrawlCommandRedactor = CrawlCommandRedactor(),
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment)
    {
        self.resolver = resolver
        self.redactor = redactor
        self.fileManager = fileManager
        self.environment = CrawlProcessEnvironment.normalized(environment)
    }

    public func run(
        installation: CrawlAppInstallation,
        action: String,
        extraArguments: [String] = [],
        timeoutSeconds: TimeInterval = 120)
        throws -> CrawlCommandResult
    {
        guard var arguments = Self.commandOverride(for: installation, action: action)
            ?? installation.manifest.commands[action]
        else {
            throw CrawlCommandRunnerError.commandUnavailable(appID: installation.id, action: action)
        }
        arguments = try Self.interpolatedArguments(arguments, installation: installation)
        arguments = Self.commandArguments(
            for: installation,
            action: action,
            commandArguments: arguments,
            extraArguments: extraArguments)

        let executionKind = installation.manifest.executionKind(configValues: installation.configValues)
        let effectiveBinaryName = Self.effectiveBinaryName(for: installation)
        let executableName: String
        if executionKind == .ssh {
            executableName = "ssh"
        } else if effectiveBinaryName != installation.manifest.binary.name {
            executableName = installation.binaryPath ?? effectiveBinaryName
        } else {
            executableName = installation.binaryPath ?? effectiveBinaryName
        }
        guard let executablePath = self.resolver.resolve(executableName) else {
            throw CrawlCommandRunnerError.executableNotFound(executableName)
        }

        var commandEnvironment = self.environment
        if let envName = installation.manifest.paths.configEnv,
           let configPath = installation.configPathOverride?.nilIfBlank
        {
            commandEnvironment[envName] = PathExpander.expandHome(configPath)
        }
        for option in installation.manifest.configOptions {
            guard let envName = option.envVar?.nilIfBlank,
                  let value = installation.configValues[option.id]?.nilIfBlank
            else { continue }
            commandEnvironment[envName] = value
        }

        if executionKind == .ssh {
            let remoteBinaryOverride = effectiveBinaryName == installation.manifest.binary.name
                ? nil
                : effectiveBinaryName
            arguments = try Self.sshArguments(
                for: installation,
                remoteArguments: arguments,
                remoteBinaryOverride: remoteBinaryOverride)
        }

        return try self.runProcess(
            appID: installation.id,
            action: action,
            executablePath: executablePath,
            arguments: arguments,
            environment: commandEnvironment,
            timeoutSeconds: timeoutSeconds)
    }
}
