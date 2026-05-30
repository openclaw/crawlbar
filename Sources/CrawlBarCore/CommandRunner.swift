import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public enum CrawlCommandRunnerError: LocalizedError, Sendable {
    case executableNotFound(String)
    case commandUnavailable(appID: CrawlAppID, action: String)
    case missingRequiredConfig(appID: CrawlAppID, optionID: String)
    case invalidRemoteTarget(appID: CrawlAppID, target: String)
    case timedOut(appID: CrawlAppID, action: String, seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(name):
            "Could not find executable: \(name)"
        case let .commandUnavailable(appID, action):
            "\(appID.rawValue) does not expose a \(action) command"
        case let .missingRequiredConfig(appID, optionID):
            "\(appID.rawValue) is missing required config: \(optionID)"
        case let .invalidRemoteTarget(appID, target):
            "\(appID.rawValue) has an invalid SSH target: \(target)"
        case let .timedOut(appID, action, seconds):
            "\(appID.rawValue) \(action) timed out after \(seconds)s"
        }
    }
}

public struct CrawlCommandRedactor: Sendable {
    public init() {}

    public func redact(_ text: String) -> String {
        var redacted = text
        let patterns: [(String, String)] = [
            (#"(?i)(Bearer[ \t]+)[^ \t\r\n"',}]+"#, "$1[REDACTED]"),
            (#"(?i)(api[_-]?key|token|secret|password|cookie|authorization)(["' \t:=]+)([^ \t\r\n"',}]+)"#, "$1$2[REDACTED]"),
            (#"(?i)\b(github_pat_)[A-Za-z0-9_]+\b"#, "$1[REDACTED]"),
            (#"(?i)\b(gh[pousr]_)[A-Za-z0-9_]+\b"#, "$1[REDACTED]"),
            (#"(?i)\b(sk-[A-Za-z0-9_-]{16,})\b"#, "[REDACTED]"),
            (#"(?i)\b(secret_)[A-Za-z0-9_]+\b"#, "$1[REDACTED]"),
            (#"(?i)(xox[aboprsxc]-)[A-Za-z0-9-]+"#, "$1[REDACTED]"),
            (#"(?i)\bmfa\.[A-Za-z0-9_-]+\b"#, "[REDACTED]"),
            (#"(?i)\b(ct0)(["' \t:=]+)([^ \t\r\n"',}]+)"#, "$1$2[REDACTED]"),
            (#"\b[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{20,}\b"#, "[REDACTED]"),
            (#"(?i)(discord[_-]?token["' \t:=]+)([^ \t\r\n"',}]+)"#, "$1[REDACTED]"),
        ]
        for (pattern, template) in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: template,
                options: [.regularExpression])
        }
        return redacted
    }
}

public final class CrawlExecutableResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let lock = NSLock()
    private var resolvedExecutables: [String: String] = [:]

    public init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = CrawlProcessEnvironment.normalized(environment)
    }

    public func resolve(_ requestedPathOrName: String) -> String? {
        self.lock.lock()
        if let cached = self.resolvedExecutables[requestedPathOrName] {
            self.lock.unlock()
            if self.isExecutable(cached) {
                return cached
            }
            self.lock.lock()
            self.resolvedExecutables.removeValue(forKey: requestedPathOrName)
            self.lock.unlock()
        } else {
            self.lock.unlock()
        }

        let resolved = self.resolveUncached(requestedPathOrName)
        self.lock.lock()
        if let resolved {
            self.resolvedExecutables[requestedPathOrName] = resolved
        } else {
            self.resolvedExecutables.removeValue(forKey: requestedPathOrName)
        }
        self.lock.unlock()
        return resolved
    }

    private func resolveUncached(_ requestedPathOrName: String) -> String? {
        let expanded = PathExpander.expandHome(requestedPathOrName)
        if expanded.contains("/") {
            return self.isExecutable(expanded) ? expanded : nil
        }

        for entry in CrawlProcessEnvironment.pathEntries(environment: self.environment) {
            let candidate = URL(fileURLWithPath: entry)
                .appendingPathComponent(expanded)
                .path
            if self.isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func isExecutable(_ path: String) -> Bool {
        self.fileManager.isExecutableFile(atPath: path)
    }
}

public struct CrawlCommandRunner: @unchecked Sendable {
    private static let timeoutTerminationGrace: DispatchTimeInterval = .milliseconds(500)

    private let resolver: CrawlExecutableResolver
    private let redactor: CrawlCommandRedactor
    private let fileManager: FileManager
    private let environment: [String: String]

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

    private func runProcess(
        appID: CrawlAppID,
        action: String,
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval)
        throws -> CrawlCommandResult
    {
        let startedAt = Date()
        let tempDirectory = self.fileManager.temporaryDirectory
            .appendingPathComponent("crawlbar-\(UUID().uuidString)", isDirectory: true)
        try self.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? self.fileManager.removeItem(at: tempDirectory) }

        let stdoutURL = tempDirectory.appendingPathComponent("stdout.log")
        let stderrURL = tempDirectory.appendingPathComponent("stderr.log")
        self.fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        self.fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()
        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            #if os(macOS) || os(Linux)
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutTerminationGrace) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
            #endif
            process.waitUntilExit()
            throw CrawlCommandRunnerError.timedOut(
                appID: appID,
                action: action,
                seconds: Int(timeoutSeconds))
        }

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()

        let stdout = try String(contentsOf: stdoutURL, encoding: .utf8)
        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)
        return CrawlCommandResult(
            appID: appID,
            action: action,
            exitCode: process.terminationStatus,
            stdout: self.redactor.redact(stdout),
            stderr: self.redactor.redact(stderr),
            startedAt: startedAt,
            finishedAt: Date())
    }

    private static func commandArguments(
        for installation: CrawlAppInstallation,
        action: String,
        commandArguments: [String],
        extraArguments: [String])
        -> [String]
    {
        if Self.wacliSearchNeedsJoinedQuery(installation: installation, action: action, extraArguments: extraArguments) {
            return commandArguments + Self.wacliSearchArguments(extraArguments)
        }

        guard installation.id == BuiltInCrawlApps.gitcrawlID,
              let repository = GitcrawlStatusSnapshot.repository(for: installation)
        else {
            return commandArguments + extraArguments
        }

        if Self.gitcrawlQueryNeedsRepository(action: action, extraArguments: extraArguments) {
            return commandArguments + [repository, "--query", extraArguments.joined(separator: " ")]
        }

        if Self.gitcrawlRefreshNeedsRepository(action: action, commandArguments: commandArguments) {
            return commandArguments + [repository] + extraArguments
        }

        return commandArguments + extraArguments
    }

    private static func interpolatedArguments(_ arguments: [String], installation: CrawlAppInstallation) throws -> [String] {
        var result: [String] = []
        for argument in arguments {
            if let optionID = Self.exactConfigTokenID(argument),
               Self.configValue(optionID, installation: installation) == nil,
               result.last == "--account"
            {
                result.removeLast()
                continue
            }
            result.append(try Self.interpolatedArgument(argument, installation: installation))
        }
        return result
    }

    private static func exactConfigTokenID(_ argument: String) -> String? {
        guard argument.hasPrefix("{config:"), argument.hasSuffix("}") else { return nil }
        let optionID = String(argument.dropFirst("{config:".count).dropLast())
        return optionID.isEmpty ? nil : optionID
    }

    private static func interpolatedArgument(_ argument: String, installation: CrawlAppInstallation) throws -> String {
        var value = argument
        while let range = value.range(of: #"\{config:([A-Za-z0-9_.-]+)\}"#, options: .regularExpression) {
            let token = String(value[range])
            let optionID = String(token.dropFirst("{config:".count).dropLast())
            guard let replacement = Self.configValue(optionID, installation: installation) else {
                throw CrawlCommandRunnerError.missingRequiredConfig(appID: installation.id, optionID: optionID)
            }
            value.replaceSubrange(range, with: replacement)
        }
        return value
    }

    private static func sshArguments(
        for installation: CrawlAppInstallation,
        remoteArguments: [String],
        remoteBinaryOverride: String? = nil)
        throws -> [String]
    {
        guard let execution = installation.manifest.execution else {
            return remoteArguments
        }
        let targetOptionID = execution.targetConfigID?.nilIfBlank ?? "remote_target"
        guard let target = Self.configValue(targetOptionID, installation: installation) else {
            throw CrawlCommandRunnerError.missingRequiredConfig(appID: installation.id, optionID: targetOptionID)
        }
        guard !target.hasPrefix("-"), !target.contains(where: { $0.isWhitespace }) else {
            throw CrawlCommandRunnerError.invalidRemoteTarget(appID: installation.id, target: target)
        }

        let remoteBinary = remoteBinaryOverride?.nilIfBlank
            ?? execution.remoteBinary?.nilIfBlank
            ?? installation.manifest.binary.name
        var commandParts = [remoteBinary] + remoteArguments
        let envFile = execution.remoteEnvFileConfigID
            .flatMap { Self.configValue($0, installation: installation) }
        let userCommand = Self.remoteShellCommand(commandParts: commandParts, envFile: envFile)
        if let runAsOptionID = execution.runAsConfigID?.nilIfBlank,
           let runAs = Self.configValue(runAsOptionID, installation: installation)
        {
            guard !runAs.hasPrefix("-"), !runAs.contains(where: { $0.isWhitespace }) else {
                throw CrawlCommandRunnerError.invalidRemoteTarget(appID: installation.id, target: runAs)
            }
            commandParts = ["sudo", "-u", runAs, "-H", "--", "sh", "-lc", userCommand]
            return ["--", target, commandParts.map(Self.shellQuoted).joined(separator: " ")]
        }
        if envFile?.nilIfBlank != nil {
            return ["--", target, ["sh", "-lc", userCommand].map(Self.shellQuoted).joined(separator: " ")]
        }
        return ["--", target, commandParts.map(Self.shellQuoted).joined(separator: " ")]
    }

    private static func remoteShellCommand(commandParts: [String], envFile: String?) -> String {
        let command = commandParts.map(Self.shellQuoted).joined(separator: " ")
        guard let envFile = envFile?.nilIfBlank else {
            return "cd ~ && exec " + command
        }
        return "cd ~ && set -a && . \(Self.shellQuoted(envFile)) && set +a && exec \(command)"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func configValue(_ optionID: String, installation: CrawlAppInstallation) -> String? {
        if let value = installation.configValues[optionID]?.nilIfBlank {
            return value
        }
        return installation.manifest.configOptions.first { $0.id == optionID }?.defaultValue?.nilIfBlank
    }

    private static func commandOverride(for installation: CrawlAppInstallation, action: String) -> [String]? {
        guard installation.id == BuiltInCrawlApps.birdclawID,
              Self.xAccessPath(for: installation) == "birdclaw"
        else { return nil }
        switch action {
        case "status", "doctor":
            return ["auth", "status", "--json"]
        case "search", "query":
            return ["--json", "search", "tweets"]
        default:
            return nil
        }
    }

    private static func effectiveBinaryName(for installation: CrawlAppInstallation) -> String {
        guard installation.id == BuiltInCrawlApps.birdclawID else {
            return installation.manifest.binary.name
        }
        return Self.xAccessPath(for: installation) == "birdclaw" ? "birdclaw" : "bird"
    }

    private static func xAccessPath(for installation: CrawlAppInstallation) -> String {
        (Self.configValue("access_path", installation: installation) ?? "bird")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func wacliSearchNeedsJoinedQuery(
        installation: CrawlAppInstallation,
        action: String,
        extraArguments: [String])
        -> Bool
    {
        guard !extraArguments.isEmpty,
              action == "search" || action == "query",
              Self.isWacliInstallation(installation)
        else { return false }
        return true
    }

    private static func isWacliInstallation(_ installation: CrawlAppInstallation) -> Bool {
        installation.id == BuiltInCrawlApps.wacliID
            || installation.id.rawValue.hasPrefix("wacli-")
            || installation.manifest.binary.name == "wacli"
    }

    private static func wacliSearchArguments(_ extraArguments: [String]) -> [String] {
        var queryParts: [String] = []
        var optionArguments: [String] = []
        var reachedOptions = false
        for argument in extraArguments {
            if argument.hasPrefix("-") {
                reachedOptions = true
            }
            if reachedOptions {
                optionArguments.append(argument)
            } else {
                queryParts.append(argument)
            }
        }
        guard queryParts.count > 1 else { return extraArguments }
        return [queryParts.joined(separator: " ")] + optionArguments
    }

    private static func gitcrawlQueryNeedsRepository(action: String, extraArguments: [String]) -> Bool {
        (action == "query" || action == "search") && !extraArguments.isEmpty && !extraArguments.contains("--query")
    }

    private static func gitcrawlRefreshNeedsRepository(action: String, commandArguments: [String]) -> Bool {
        guard action == "refresh" || action == "sync",
              let command = commandArguments.first,
              command == "refresh" || command == "sync"
        else { return false }
        return !commandArguments.dropFirst().contains { !$0.hasPrefix("-") && $0.contains("/") }
    }
}
