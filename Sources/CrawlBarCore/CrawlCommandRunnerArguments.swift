import Foundation

extension CrawlCommandRunner {
    static func commandArguments(
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

    static func interpolatedArguments(_ arguments: [String], installation: CrawlAppInstallation) throws -> [String] {
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

    static func sshArguments(
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

    static func commandOverride(for installation: CrawlAppInstallation, action: String) -> [String]? {
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

    static func effectiveBinaryName(for installation: CrawlAppInstallation) -> String {
        guard installation.id == BuiltInCrawlApps.birdclawID else {
            return installation.manifest.binary.name
        }
        return Self.xAccessPath(for: installation) == "birdclaw" ? "birdclaw" : "bird"
    }

    static func configValue(_ optionID: String, installation: CrawlAppInstallation) -> String? {
        if let value = installation.configValues[optionID]?.nilIfBlank {
            return value
        }
        return installation.manifest.configOptions.first { $0.id == optionID }?.defaultValue?.nilIfBlank
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
