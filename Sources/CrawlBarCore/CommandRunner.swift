import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public enum CrawlCommandRunnerError: LocalizedError, Sendable {
    case executableNotFound(String)
    case commandUnavailable(appID: CrawlAppID, action: String)
    case timedOut(appID: CrawlAppID, action: String, seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(name):
            "Could not find executable: \(name)"
        case let .commandUnavailable(appID, action):
            "\(appID.rawValue) does not expose a \(action) command"
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

public struct CrawlExecutableResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]

    public init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = CrawlProcessEnvironment.normalized(environment)
    }

    public func resolve(_ requestedPathOrName: String) -> String? {
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
        guard var arguments = installation.manifest.commands[action] else {
            throw CrawlCommandRunnerError.commandUnavailable(appID: installation.id, action: action)
        }
        arguments = Self.commandArguments(
            for: installation,
            action: action,
            commandArguments: arguments,
            extraArguments: extraArguments)

        let executableName = installation.binaryPath ?? installation.manifest.binary.name
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
