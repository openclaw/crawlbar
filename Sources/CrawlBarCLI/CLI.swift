import CrawlBarCore
import Foundation

@main
enum CrawlBarCLI {
    static func main() {
        do {
            try Self.run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            CLIOutput.writeError(error.localizedDescription)
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            Self.printHelp()
            return
        }

        let options = CLIOptions(arguments.dropFirst())
        let registry = CrawlAppRegistry()
        let runner = CrawlCommandRunner()
        let statusService = CrawlStatusService(runner: runner)
        let installer = CrawlInstaller()

        switch command {
        case "apps":
            try Self.printApps(registry: registry, json: options.json)
        case "logs":
            try Self.printLogs(json: options.json)
        case "metadata":
            try Self.printMetadata(
                registry: registry,
                appID: options.appID,
                json: options.json,
                diagnostics: options.diagnostics)
        case "status":
            try Self.printStatus(registry: registry, statusService: statusService, options: options)
        case "backup":
            try Self.backup(registry: registry, statusService: statusService, json: options.json, appID: options.requiredAppID())
        case "folder":
            try Self.printFolder(registry: registry, statusService: statusService, json: options.json, appID: options.requiredAppID())
        case "doctor", "refresh":
            try Self.runAction(command, registry: registry, runner: runner, json: options.json, appID: options.requiredAppID())
        case "install":
            try Self.install(registry: registry, installer: installer, json: options.json, appID: options.requiredAppID())
        case "query":
            try Self.query(registry: registry, runner: runner, options: options)
        case "action":
            guard let action = options.positionals.first else {
                throw CLIError.usage("action requires an action id")
            }
            try Self.runAction(action, registry: registry, runner: runner, json: options.json, appID: options.requiredAppID())
        case "config":
            try Self.runConfig(options, registry: registry)
        case "dev":
            try Self.runDev(options, registry: registry)
        case "help", "--help", "-h":
            Self.printHelp()
        default:
            throw CLIError.usage("unknown command: \(command)")
        }
    }

    private static func printApps(registry: CrawlAppRegistry, json: Bool) throws {
        let apps = try registry.installations(includeDisabled: true).map(CLIApp.init)
        if json {
            try CLIOutput.writeJSON(apps)
            return
        }
        for app in apps {
            let marker = app.availability == .comingSoon ? "soon" : (app.enabled ? (app.available ? "ok" : "missing") : "disabled")
            print("\(marker)\t\(app.id)\t\(app.displayName)")
        }
    }

    private static func printMetadata(
        registry: CrawlAppRegistry,
        appID: CrawlAppID?,
        json: Bool,
        diagnostics: Bool)
        throws
    {
        if diagnostics {
            let config = try registry.loadConfig()
            let diagnostics = CrawlManifestCatalog().diagnostics(config: config)
            if json {
                try CLIOutput.writeJSON(diagnostics)
                return
            }
            if diagnostics.isEmpty {
                print("ok")
                return
            }
            for diagnostic in diagnostics {
                print("warning\t\(diagnostic.path)\t\(diagnostic.message)")
            }
            return
        }

        let installations = try registry.installations(includeDisabled: true)
        let manifests = installations
            .filter { appID == nil || $0.id == appID }
            .map(\.manifest)
        if json {
            try CLIOutput.writeJSON(manifests)
            return
        }
        for manifest in manifests {
            print("\(manifest.id.rawValue)\t\(manifest.displayName)\t\(manifest.binary.name)")
        }
    }

    private static func printLogs(json: Bool) throws {
        let logs = CrawlActionLogStore().recent(limit: 50).map { $0.path }
        if json {
            try CLIOutput.writeJSON(logs)
            return
        }
        logs.forEach { print($0) }
    }

    private static func printStatus(
        registry: CrawlAppRegistry,
        statusService: CrawlStatusService,
        options: CLIOptions)
        throws
    {
        let requestedID = options.appID
        let installations = try registry.installationsForStatus(includeDisabled: true)
            .filter { requestedID == nil || requestedID == CrawlAppID(rawValue: "all") || $0.id == requestedID }
        let statuses = installations.map { installation -> CrawlAppStatus in
            statusService.status(for: installation, timeoutSeconds: 30)
        }

        if options.json {
            try CLIOutput.writeJSON(statuses)
            return
        }
        for status in statuses {
            print("\(status.state.rawValue)\t\(status.appID.rawValue)\t\(status.summary)")
        }
    }

    private static func runAction(
        _ action: String,
        registry: CrawlAppRegistry,
        runner: CrawlCommandRunner,
        json: Bool,
        appID: CrawlAppID)
        throws
    {
        guard let installation = try registry.installation(for: appID, includeSecrets: true) else {
            throw CLIError.usage("unknown app: \(appID.rawValue)")
        }
        guard installation.enabled else {
            throw CLIError.usage("\(appID.rawValue) is disabled")
        }
        guard installation.binaryPath != nil else {
            throw CLIError.usage("\(installation.manifest.binary.name) is not on PATH")
        }
        let result = try runner.run(installation: installation, action: action, timeoutSeconds: 600)
        _ = try? CrawlActionLogStore().save(result)
        if json {
            try CLIOutput.writeJSON(result)
            if !result.succeeded {
                Foundation.exit(Int32(result.exitCode))
            }
            return
        }
        print(result.stdout.nilIfBlank ?? result.stderr.nilIfBlank ?? "exit \(result.exitCode)")
        if !result.succeeded {
            Foundation.exit(Int32(result.exitCode))
        }
    }

    private static func install(
        registry: CrawlAppRegistry,
        installer: CrawlInstaller,
        json: Bool,
        appID: CrawlAppID)
        throws
    {
        guard let installation = try registry.installationForStatus(for: appID) else {
            throw CLIError.usage("unknown app: \(appID.rawValue)")
        }
        guard installation.manifest.availability == .available else {
            throw CLIError.usage("\(installation.manifest.displayName) is coming soon")
        }
        let result = try installer.install(installation)
        _ = try? CrawlActionLogStore().save(result)
        if json {
            try CLIOutput.writeJSON(result)
            return
        }
        print(result.stdout.nilIfBlank ?? result.stderr.nilIfBlank ?? "installed \(installation.manifest.binary.name)")
    }

    private static func query(registry: CrawlAppRegistry, runner: CrawlCommandRunner, options: CLIOptions) throws {
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
                .filter { Self.queryAction(for: $0, queryArguments: queryArguments) != nil }
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
                return try runner.run(
                    installation: installation,
                    action: action,
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

    private static func queryAction(
        for installation: CrawlAppInstallation,
        queryArguments: [String])
        -> String?
    {
        CrawlQueryActionResolver.action(for: installation.manifest, queryArguments: queryArguments)
    }

    private static func backup(
        registry: CrawlAppRegistry,
        statusService: CrawlStatusService,
        json: Bool,
        appID: CrawlAppID)
        throws
    {
        let status = try Self.status(for: appID, registry: registry, statusService: statusService)
        let backup = try CrawlDatabaseBackupStore.backup(status: status)
        if json {
            try CLIOutput.writeJSON(backup)
            return
        }
        print(backup.directory)
    }

    private static func printFolder(
        registry: CrawlAppRegistry,
        statusService: CrawlStatusService,
        json: Bool,
        appID: CrawlAppID)
        throws
    {
        let status = try Self.status(for: appID, registry: registry, statusService: statusService)
        guard let path = status.databases.first(where: { $0.isPrimary })?.path ?? status.databasePath else {
            throw CLIError.usage("no database folder for \(appID.rawValue)")
        }
        let folder = URL(fileURLWithPath: PathExpander.expandHome(path)).deletingLastPathComponent().path
        if json {
            try CLIOutput.writeJSON(["app_id": appID.rawValue, "folder": folder])
            return
        }
        print(folder)
    }

    private static func status(
        for appID: CrawlAppID,
        registry: CrawlAppRegistry,
        statusService: CrawlStatusService)
        throws -> CrawlAppStatus
    {
        guard let installation = try registry.installationForStatus(for: appID) else {
            throw CLIError.usage("unknown app: \(appID.rawValue)")
        }
        return statusService.status(for: installation, timeoutSeconds: 30)
    }

    private static func printHelp() {
        print("""
        crawlbar commands:
          apps [--json]
          backup --app <id> [--json]
          folder --app <id> [--json]
          logs [--json]
          metadata [--app <id>] [--json] [--diagnostics]
          status [--app <id|all>] [--json]
          install --app <id> [--json]
          query [--app <id|all>] [--json] -- <text-or-sql>
          doctor --app <id> [--json]
          refresh --app <id> [--json]
          action <action-id> --app <id> [--json]
          config path|validate|init
          config get --app <id> [--key <id>] [--json] [--reveal]
          config set --app <id> --key <id> --value <value> [--json]
          dev register --app <id> --binary <path> [--json]
          dev unregister --app <id> [--json]
          dev list [--json]
        """)
    }
}
