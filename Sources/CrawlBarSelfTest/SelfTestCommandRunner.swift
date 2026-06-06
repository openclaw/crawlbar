import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testConfigValuesReachCommandEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-env-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent("print-env.sh")
        try Data("""
        #!/bin/sh
        if [ "$#" -gt 0 ]; then
          printf '%s|%s' "$CRAWLBAR_TEST_VALUE" "$*"
        else
          printf '%s' "$CRAWLBAR_TEST_VALUE"
        fi
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "envcrawl"),
            displayName: "Env Crawl",
            description: "A test crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "terminal", accentColor: "#123456"),
            paths: .init(),
            commands: ["status": [], "query": ["query"]],
            capabilities: [.status],
            configOptions: [
                .init(id: "test_value", label: "Test Value", envVar: "CRAWLBAR_TEST_VALUE"),
            ])
        let installation = CrawlAppInstallation(
            manifest: manifest,
            binaryPath: scriptURL.path,
            configValues: ["test_value": "from-config"])
        let result = try CrawlCommandRunner().run(installation: installation, action: "status", timeoutSeconds: 5)
        try Self.expect(result.stdout == "from-config", "config values reach crawler command environment")
        let queryResult = try CrawlCommandRunner().run(
            installation: installation,
            action: "query",
            extraArguments: ["select count(*) from items"],
            timeoutSeconds: 5)
        try Self.expect(queryResult.stdout == "from-config|query select count(*) from items", "query arguments reach crawler commands")
    }

    static func testExecutableResolverUsesMacCliFallbackPaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-path-\(UUID().uuidString)", isDirectory: true)
        let localBinURL = directory.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: localBinURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = localBinURL.appendingPathComponent("fallbackcrawl")
        try Data("""
        #!/bin/sh
        printf '%s' "$PATH"
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let environment = [
            "HOME": directory.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        let resolver = CrawlExecutableResolver(environment: environment)
        try Self.expect(
            resolver.resolve("fallbackcrawl") == scriptURL.path,
            "resolver checks user CLI fallback paths")

        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "fallbackcrawl"),
            displayName: "Fallback Crawl",
            description: "A fallback PATH crawler",
            binary: .init(name: "fallbackcrawl"),
            branding: .init(symbolName: "terminal", accentColor: "#123456"),
            paths: .init(),
            commands: ["status": []],
            capabilities: [.status])
        let installation = CrawlAppInstallation(manifest: manifest, binaryPath: "fallbackcrawl")
        let result = try CrawlCommandRunner(resolver: resolver, environment: environment)
            .run(installation: installation, action: "status", timeoutSeconds: 5)

        try Self.expect(
            result.stdout.split(separator: ":").contains(Substring(localBinURL.path)),
            "runner passes normalized fallback PATH to crawlers")
        try Self.expect(
            CrawlProcessEnvironment.normalized(["PATH": "/usr/bin"])["HOME"]?.isEmpty == false,
            "normalized environment supplies HOME for launchd crawler commands")
    }

    static func testRegistryResolvesBirdclawAccessPathBinary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-birdclaw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let binaryURL = directory.appendingPathComponent("birdclaw")
        try Data("#!/bin/sh\n".utf8).write(to: binaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let configURL = directory.appendingPathComponent("config.json")
        let store = CrawlBarConfigStore(fileURL: configURL)
        try store.save(CrawlBarConfig(apps: [
            CrawlBarAppConfig(
                id: BuiltInCrawlApps.birdclawID,
                configValues: ["access_path": "birdclaw"]),
        ]))
        let registry = CrawlAppRegistry(
            configStore: store,
            resolver: CrawlExecutableResolver(environment: [
                "HOME": directory.path,
                "PATH": directory.path,
            ]))
        let installation = try registry.installation(for: BuiltInCrawlApps.birdclawID)
        try Self.expect(installation?.binaryPath == binaryURL.path, "Birdclaw access path resolves birdclaw binary")
    }

    static func testRemoteSshExecutionBuildsCommand() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-remote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent("ssh")
        try Data("""
        #!/bin/sh
        printf '%s' "$*"
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let environment = [
            "HOME": directory.path,
            "PATH": directory.path,
        ]
        let runner = CrawlCommandRunner(
            resolver: CrawlExecutableResolver(environment: environment),
            environment: environment)

        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "wacli-test"),
            displayName: "WhatsApp Test",
            description: "A remote WhatsApp crawler",
            binary: .init(name: "wacli"),
            execution: .init(
                kind: .local,
                kindConfigID: "execution_mode",
                targetConfigID: "remote_target",
                runAsConfigID: "remote_run_as",
                remoteBinary: "wacli"),
            branding: .init(symbolName: "message.circle", accentColor: "#25D366"),
            paths: .init(),
            commands: ["search": ["--account", "{config:account}", "--read-only", "--json", "messages", "search"]],
            capabilities: [.search],
            configOptions: [
                .init(id: "execution_mode", label: "Run Location", kind: .choice, defaultValue: "local", choices: ["local", "remote"]),
                .init(id: "account", label: "Account", defaultValue: "personal"),
            ])
        let installation = CrawlAppInstallation(
            manifest: manifest,
            binaryPath: scriptURL.path,
            configValues: [
                "execution_mode": "remote",
                "remote_target": "user@example-host",
                "remote_run_as": "crawl",
            ])
        let result = try runner.run(
            installation: installation,
            action: "search",
            extraArguments: ["hello", "world"],
            timeoutSeconds: 5)

        try Self.expect(
            result.stdout == #"-- user@example-host 'sudo' '-u' 'crawl' '-H' '--' 'sh' '-lc' 'cd ~ && exec '\''wacli'\'' '\''--account'\'' '\''personal'\'' '\''--read-only'\'' '\''--json'\'' '\''messages'\'' '\''search'\'' '\''hello world'\'''"#,
            "remote SSH execution builds a quoted remote command with config defaults")

        let optionTargetInstallation = CrawlAppInstallation(
            manifest: manifest,
            binaryPath: scriptURL.path,
            configValues: [
                "execution_mode": "remote",
                "remote_target": "-oProxyCommand=/tmp/hook",
            ])
        do {
            _ = try runner.run(
                installation: optionTargetInstallation,
                action: "search",
                extraArguments: ["hello"],
                timeoutSeconds: 5)
            throw SelfTestError.failed("remote SSH target rejects option-looking values")
        } catch CrawlCommandRunnerError.invalidRemoteTarget {
        }

        let localInstallation = CrawlAppInstallation(
            manifest: manifest,
            binaryPath: scriptURL.path,
            configValues: ["execution_mode": "local"])
        let localResult = try runner.run(
            installation: localInstallation,
            action: "search",
            extraArguments: ["hello", "world"],
            timeoutSeconds: 5)
        try Self.expect(
            localResult.stdout == "--account personal --read-only --json messages search hello world",
            "local execution mode bypasses SSH and uses the crawler binary")

        let remoteBirdclawInstallation = CrawlAppInstallation(
            manifest: BuiltInCrawlApps.birdclaw,
            binaryPath: scriptURL.path,
            configValues: [
                "access_path": "birdclaw",
                "execution_mode": "remote",
                "remote_target": "user@example-host",
                "remote_run_as": "crawl",
            ])
        let birdclawResult = try runner.run(
            installation: remoteBirdclawInstallation,
            action: "status",
            timeoutSeconds: 5)
        try Self.expect(
            birdclawResult.stdout == #"-- user@example-host 'sudo' '-u' 'crawl' '-H' '--' 'sh' '-lc' 'cd ~ && exec '\''birdclaw'\'' '\''auth'\'' '\''status'\'' '\''--json'\'''"#,
            "X remote execution can use the Birdclaw/xurl access path")

        let customBirdclawURL = directory.appendingPathComponent("custom-birdclaw")
        try Data("""
        #!/bin/sh
        printf 'custom:%s' "$*"
        """.utf8).write(to: customBirdclawURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: customBirdclawURL.path)
        let localBirdclawOverride = CrawlAppInstallation(
            manifest: BuiltInCrawlApps.birdclaw,
            binaryPath: customBirdclawURL.path,
            configValues: ["access_path": "birdclaw"])
        let localBirdclawResult = try runner.run(
            installation: localBirdclawOverride,
            action: "status",
            timeoutSeconds: 5)
        try Self.expect(
            localBirdclawResult.stdout == "custom:auth status --json",
            "Birdclaw access path preserves binary overrides")

        let envManifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "envcrawl-test"),
            displayName: "Env Crawl Test",
            description: "A remote crawler that needs an env file",
            binary: .init(name: "envcrawl-local"),
            execution: .init(
                kind: .local,
                kindConfigID: "execution_mode",
                targetConfigID: "remote_target",
                runAsConfigID: "remote_run_as",
                remoteEnvFileConfigID: "remote_env_file",
                remoteBinary: "envcrawl"),
            branding: .init(symbolName: "terminal", accentColor: "#123456"),
            paths: .init(),
            commands: ["status": ["status", "--json"]],
            capabilities: [.status],
            configOptions: [
                .init(id: "execution_mode", label: "Run Location", kind: .choice, defaultValue: "local", choices: ["local", "remote"]),
                .init(id: "remote_env_file", label: "Remote Env File"),
            ])
        let envInstallation = CrawlAppInstallation(
            manifest: envManifest,
            binaryPath: scriptURL.path,
            configValues: [
                "execution_mode": "remote",
                "remote_target": "user@example-host",
                "remote_run_as": "crawl",
                "remote_env_file": "/run/example/env",
            ])
        let envResult = try runner.run(
            installation: envInstallation,
            action: "status",
            timeoutSeconds: 5)
        try Self.expect(
            envResult.stdout == #"-- user@example-host 'sudo' '-u' 'crawl' '-H' '--' 'sh' '-lc' 'cd ~ && set -a && . '\''/run/example/env'\'' && set +a && exec '\''envcrawl'\'' '\''status'\'' '\''--json'\'''"#,
            "remote SSH execution can source an env file before exec")
    }
}
