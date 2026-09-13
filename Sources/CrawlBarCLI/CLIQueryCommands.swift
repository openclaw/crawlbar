import CrawlBarCore
import Foundation

extension CrawlBarCLI {
    static func query(registry: CrawlAppRegistry, runner: CrawlCommandRunner, options: CLIOptions) throws {
        let queryArguments = options.positionals
        guard !queryArguments.isEmpty else {
            throw CLIError.usage("query requires text or SQL")
        }

        let isAllApps = options.appID == nil || options.appID == CrawlAppID(rawValue: "all")
        let installations: [CrawlAppInstallation]
        if !isAllApps, let appID = options.appID {
            guard let installation = try registry.installation(for: appID, includeSecrets: false) else {
                throw CLIError.usage("unknown app: \(appID.rawValue)")
            }
            guard installation.manifest.availability == .available else {
                throw CLIError.usage("\(installation.manifest.displayName) is coming soon")
            }
            guard installation.enabled else {
                throw CLIError.usage("\(appID.rawValue) is disabled")
            }
            guard installation.binaryPath != nil else {
                throw CLIError.usage("\(installation.manifest.binary.name) is not on PATH")
            }
            installations = [installation]
        } else {
            installations = try registry.availableInstallations(includeSecrets: false)
                .filter { CrawlQueryActionResolver.action(for: $0.manifest, queryArguments: queryArguments) != nil }
        }
        guard !installations.isEmpty else {
            throw CLIError.usage("no query-capable crawlers are enabled and on PATH")
        }

        let results = installations.map { installation -> CrawlCommandResult in
            guard let action = CrawlQueryActionResolver.action(
                for: installation.manifest,
                queryArguments: queryArguments)
            else {
                return CrawlCommandResult(
                    appID: installation.id,
                    action: "query",
                    exitCode: 64,
                    stdout: "",
                    stderr: "\(installation.id.rawValue) does not expose a query command",
                    startedAt: Date(),
                    finishedAt: Date())
            }
            do {
                return try Self.runCommand(
                    installation: installation,
                    action: action,
                    registry: registry,
                    runner: runner,
                    extraArguments: queryArguments,
                    timeoutSeconds: 120)
            } catch {
                return CrawlCommandResult(
                    appID: installation.id,
                    action: action,
                    exitCode: 1,
                    stdout: "",
                    stderr: error.localizedDescription,
                    startedAt: Date(),
                    finishedAt: Date())
            }
        }

        if options.json {
            try CLIOutput.writeJSON(results)
        } else if results.count == 1, let result = results.first {
            print(result.stdout.nilIfBlank ?? result.stderr.nilIfBlank ?? "exit \(result.exitCode)")
        } else {
            for result in results {
                print("== \(result.appID.rawValue) ==")
                print(result.stdout.nilIfBlank ?? result.stderr.nilIfBlank ?? "exit \(result.exitCode)")
            }
        }

        let hasFailures = results.contains { !$0.succeeded }
        let hasSuccesses = results.contains { $0.succeeded }
        if hasFailures, (!isAllApps || !hasSuccesses) {
            Foundation.exit(1)
        }
    }
}
