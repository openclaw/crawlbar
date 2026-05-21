import CrawlBarCore
import Foundation

@main
enum CrawlBarSelfTest {
    static func main() throws {
        try Self.testAppIDSortsByRawValue()
        try Self.testDefaultConfigNormalizesBuiltInApps()
        try Self.testConfigStoreRoundTrips()
        try Self.testExternalManifestCatalog()
        try Self.testNativeConfigRoundTrips()
        try Self.testStatusSecretsLoadFromNativeConfig()
        try Self.testStatusMapperNormalizesCounts()
        try Self.testActionFailuresPreserveStatusMetadata()
        try Self.testActionLogStoreReadsRecentResults()
        try Self.testQueryActionResolverSkipsSQLForPlainText()
        try Self.testExecutableResolverUsesMacCliFallbackPaths()
        try Self.testConfigValuesReachCommandEnvironment()
        try Self.testGitcrawlCommandArgumentsInferRepository()
        try Self.testCommandTimeoutEscalates()
        try Self.testDatabaseBackupCopiesFiles()
        try Self.testRedactorScrubsSecrets()
        print("crawlbar selftest ok")
    }

    private static func testAppIDSortsByRawValue() throws {
        try Self.expect(
            [CrawlAppID(rawValue: "b"), CrawlAppID(rawValue: "a")].sorted().map(\.rawValue) == ["a", "b"],
            "app ids sort by raw value")
    }

    private static func testDefaultConfigNormalizesBuiltInApps() throws {
        let config = CrawlBarConfig(apps: []).normalized()
        try Self.expect(config.version == CrawlBarConfig.currentVersion, "config version normalizes")
        try Self.expect(config.apps.map(\.id) == BuiltInCrawlApps.all.map(\.id), "built-in apps are present")
        try Self.expect(config.appConfig(for: BuiltInCrawlApps.gogcliID)?.enabled == false, "coming soon apps normalize disabled")
        try Self.expect(config.appConfig(for: BuiltInCrawlApps.gogcliID)?.showInMenuBar == false, "coming soon apps stay out of menu bar")
        try Self.expect(config.manifestDirectories == ["~/.crawlbar/apps"], "manifest directory default is present")
    }

    private static func testConfigStoreRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("config.json")
        let store = CrawlBarConfigStore(fileURL: url)
        let config = CrawlBarConfig(
            refreshFrequency: .hourly,
            apps: [CrawlBarAppConfig(
                id: BuiltInCrawlApps.gitcrawlID,
                enabled: false,
                configValues: ["embedding_model": "text-embedding-3-large"])])

        try store.save(config)
        guard let loaded = try store.load() else {
            throw SelfTestError.failed("config loads after save")
        }

        try Self.expect(loaded.refreshFrequency == .hourly, "refresh frequency round trips")
        try Self.expect(loaded.appConfig(for: BuiltInCrawlApps.gitcrawlID)?.enabled == false, "app enablement round trips")
        try Self.expect(loaded.appConfig(for: BuiltInCrawlApps.gitcrawlID)?.configValues["embedding_model"] == "text-embedding-3-large", "app config values round trip")
        try Self.expect(loaded.apps.count == BuiltInCrawlApps.all.count, "config store normalizes built-ins")
    }

    private static func testExternalManifestCatalog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "customcrawl"),
            displayName: "Custom Crawl",
            description: "A custom crawl app",
            binary: .init(name: "customcrawl"),
            branding: .init(symbolName: "square.grid.2x2", accentColor: "#123456"),
            paths: .init(defaultConfig: "~/.customcrawl/config.toml"),
            commands: ["status": ["status", "--json"]],
            capabilities: [.status])
        let data = try CrawlCoding.makeJSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("customcrawl.json"))
        try Data("""
        {
          "schema_version": "crawlkit.control.v1",
          "id": "objectcrawl",
          "display_name": "Object Crawl",
          "description": "A crawlkit manifest",
          "binary": {"name": "objectcrawl"},
          "branding": {"symbol_name": "tray", "accent_color": "#123456"},
          "paths": {"default_config": "~/.objectcrawl/config.toml"},
          "commands": {
            "status": {"title": "Status", "argv": ["objectcrawl", "status", "--json"], "json": true},
            "sync": {"title": "Sync", "argv": ["objectcrawl", "sync", "--json"], "json": true, "mutates": true},
            "query": {"title": "Query", "argv": ["objectcrawl", "--json", "sql", "select count(*) from things"], "json": true},
            "tap": {"title": "Desktop", "argv": ["objectcrawl", "tap", "--json"], "json": true, "mutates": true}
          },
          "capabilities": ["metadata", "status", "sync", "tap", "git-share"],
          "privacy": {"exports_secrets": false}
        }
        """.utf8).write(to: directory.appendingPathComponent("objectcrawl.json"))
        try Data("""
        {
          "id": "cachecrawl",
          "display_name": "Cache Crawl",
          "description": "A desktop cache test manifest",
          "binary": {"name": "cachecrawl"},
          "branding": {"symbol_name": "tray", "accent_color": "#123456"},
          "paths": {"default_config": "~/.cachecrawl/config.toml"},
          "commands": {
            "desktop-cache-import": ["sync", "--source", "desktop-cache"]
          }
        }
        """.utf8).write(to: directory.appendingPathComponent("cachecrawl.json"))
        try Data("{ bad json".utf8).write(to: directory.appendingPathComponent("broken.json"))

        let config = CrawlBarConfig(manifestDirectories: [directory.path])
        let catalog = CrawlManifestCatalog()
        let manifests = catalog.manifests(config: config)
        let diagnostics = catalog.diagnostics(config: config)
        let configURL = directory.appendingPathComponent("config.json")
        let store = CrawlBarConfigStore(fileURL: configURL)
        try store.save(config)
        let registry = CrawlAppRegistry(configStore: store, catalog: catalog)
        let installations = try registry.installations(includeDisabled: true)
        try Self.expect(manifests.contains { $0.id == manifest.id }, "external manifests load from disk")
        guard let objectManifest = manifests.first(where: { $0.id.rawValue == "objectcrawl" }) else {
            throw SelfTestError.failed("crawlkit command-object manifests load from disk")
        }
        try Self.expect(objectManifest.commands["status"] == ["status", "--json"], "crawlkit command argv strips binary")
        try Self.expect(objectManifest.commands["query"] == ["--json", "sql"], "crawlkit query sample SQL is stripped")
        try Self.expect(objectManifest.commands["refresh"] == ["sync", "--json"], "crawlkit sync command aliases to refresh")
        try Self.expect(objectManifest.commands["desktop-cache-import"] == ["tap", "--json"], "crawlkit tap command aliases to desktop cache import")
        try Self.expect(objectManifest.capabilities.contains(.refresh), "crawlkit sync capability maps to refresh")
        try Self.expect(objectManifest.capabilities.contains(.search), "crawlkit SQL/query capability maps to search")
        try Self.expect(objectManifest.capabilities.contains(.desktopCache), "crawlkit tap capability maps to desktop cache")
        try Self.expect(objectManifest.capabilities.contains(.publish), "crawlkit git-share capability maps to publish")
        guard let cacheManifest = manifests.first(where: { $0.id.rawValue == "cachecrawl" }) else {
            throw SelfTestError.failed("desktop cache manifest loads from disk")
        }
        try Self.expect(cacheManifest.capabilities.contains(.desktopCache), "desktop-cache-import command maps to desktop cache")
        try Self.expect(diagnostics.contains { $0.path.hasSuffix("broken.json") }, "external manifest parse errors are reported")
        try Self.expect(installations.contains { $0.id == manifest.id }, "external manifests appear as installations")
        try Self.expect(BuiltInCrawlApps.gitcrawl.configOptions.contains { $0.id == "embedding_model" }, "built-in config options exist")
        try Self.expect(!BuiltInCrawlApps.gitcrawl.needsSecretsForStatus, "built-in status avoids launch keychain reads")
        let secretStatusManifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "secretstatus"),
            displayName: "Secret Status",
            description: "Status requires an env secret",
            binary: .init(name: "secretstatus"),
            branding: .init(symbolName: "lock", accentColor: "#123456"),
            paths: .init(),
            commands: ["status": ["status", "--json"]],
            capabilities: [.status],
            configOptions: [.init(id: "token", label: "Token", kind: .secret, envVar: "SECRET_STATUS_TOKEN")])
        try Self.expect(secretStatusManifest.needsSecretsForStatus, "external secret status can opt into keychain reads")
        try Self.expect(BuiltInCrawlApps.slacrawl.privacy.containsPrivateMessages, "Slack privacy metadata flags local messages")
        try Self.expect(BuiltInCrawlApps.notcrawl.privacy.localOnlyScopes.contains("workspace pages"), "Notion privacy metadata flags workspace pages")
        try Self.expect(BuiltInCrawlApps.slacrawl.install?.package == "vincentkoc/tap/slacrawl", "built-in install metadata exists")
        try Self.expect(BuiltInCrawlApps.gogcli.availability == .comingSoon, "coming soon manifests are marked unavailable")
        try Self.expect(BuiltInCrawlApps.graincrawl.availability == .available, "graincrawl is available")
        try Self.expect(BuiltInCrawlApps.graincrawl.commands["status"] == ["status", "--json"], "graincrawl uses crawlkit status command")
        try Self.expect(
            BuiltInCrawlApps.graincrawl.commands["refresh"] == ["sync", "--json"],
            "graincrawl refresh honors configured source")
        try Self.expect(
            BuiltInCrawlApps.graincrawl.commands["desktop-cache-import"] == ["sync", "--source", "desktop-cache", "--json"],
            "graincrawl exposes explicit desktop cache import")
        try Self.expect(BuiltInCrawlApps.graincrawl.capabilities.contains(.desktopCache), "graincrawl advertises desktop cache capability")
        try Self.expect(
            BuiltInCrawlApps.graincrawl.commands["query"] == ["--json", "sql"],
            "graincrawl query emits JSON by default")
        try Self.expect(BuiltInCrawlApps.graincrawl.commands["unlock"] == ["unlock", "--json"], "graincrawl exposes unlock action")
        try Self.expect(BuiltInCrawlApps.graincrawl.branding.bundleIdentifier == "com.granola.app", "graincrawl uses native Granola icon")
        try Self.expect(BuiltInCrawlApps.gitcrawl.commands["status"] == ["status", "--json"], "gitcrawl uses fast status command")
        try Self.expect(BuiltInCrawlApps.gitcrawl.commands["refresh"] == ["sync", "--json"], "gitcrawl keeps refresh action wired")
        try Self.expect(BuiltInCrawlApps.slacrawl.commands["query"] == ["sql"], "Slack exposes query action")
        try Self.expect(BuiltInCrawlApps.slacrawl.commands["search"] == ["--json", "search"], "Slack exposes text search action")
        try Self.expect(BuiltInCrawlApps.discrawl.commands["query"] == nil, "Discord does not advertise stale SQL action")
        try Self.expect(!BuiltInCrawlApps.discrawl.capabilities.contains(.search), "Discord search capability waits for upstream metadata")
        try Self.expect(BuiltInCrawlApps.notcrawl.capabilities.contains(.desktopCache), "Notion advertises desktop cache capability")
        try Self.expect(BuiltInCrawlApps.gitcrawl.configSections.contains { $0.id == "github" }, "built-in config sections exist")
    }

    private static func testNativeConfigRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-native-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.toml")
        try Data("""
        [openai]
        api_key = "from-file"
        """.utf8).write(to: configURL)

        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "tomlcrawl"),
            displayName: "TOML Crawl",
            description: "A TOML test crawler",
            binary: .init(name: "tomlcrawl"),
            branding: .init(symbolName: "terminal", accentColor: "#123456"),
            paths: .init(defaultConfig: configURL.path),
            commands: [:],
            capabilities: [],
            configOptions: [
                .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, configKey: "openai.api_key"),
                .init(id: "embedding_model", label: "Embedding model", kind: .choice, configKey: "embeddings.model"),
                .init(id: "sync_limit", label: "Sync limit", kind: .number, configKey: "sync.default_limit"),
            ])
        var appConfig = CrawlBarAppConfig(id: manifest.id)
        let nativeStore = CrawlNativeConfigStore()
        try Self.expect(
            nativeStore.resolvedConfigValues(appConfig: appConfig, manifest: manifest)["openai_api_key"] == "from-file",
            "native TOML config values load")
        try Self.expect(
            nativeStore.resolvedConfigValues(appConfig: appConfig, manifest: manifest, includeSecrets: false)["openai_api_key"] == nil,
            "native TOML secrets stay out of non-secret loads")

        appConfig.configValues = nativeStore.resolvedConfigValues(appConfig: appConfig, manifest: manifest)
        appConfig.configValues["embedding_model"] = "text-embedding-3-large"
        appConfig.configValues["sync_limit"] = "100"
        try nativeStore.write(appConfig: appConfig, manifest: manifest)
        let content = try String(contentsOf: configURL, encoding: .utf8)
        try Self.expect(content.contains("api_key = \"from-file\""), "native TOML values preserve existing keys")
        try Self.expect(content.contains("[embeddings]"), "native TOML section writes")
        try Self.expect(content.contains("model = \"text-embedding-3-large\""), "native TOML value writes")
        try Self.expect(content.contains("default_limit = 100"), "native TOML number writes without quotes")

        appConfig.configValues.removeValue(forKey: "openai_api_key")
        try nativeStore.write(appConfig: appConfig, manifest: manifest)
        let clearedContent = try String(contentsOf: configURL, encoding: .utf8)
        try Self.expect(clearedContent.contains("api_key = \"from-file\""), "native TOML secret keys preserve when omitted")
        try nativeStore.write(appConfig: appConfig, manifest: manifest, clearMissingSecretIDs: ["openai_api_key"])
        let explicitlyClearedContent = try String(contentsOf: configURL, encoding: .utf8)
        try Self.expect(!explicitlyClearedContent.contains("api_key ="), "native TOML secret keys clear when explicit")
    }

    private static func testStatusSecretsLoadFromNativeConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-status-secret-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent("secret-status.sh")
        try Data("""
        #!/bin/sh
        printf '{"state":"ok"}'
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let nativeConfigURL = directory.appendingPathComponent("status.toml")
        try Data("""
        [auth]
        token = "from-native"
        """.utf8).write(to: nativeConfigURL)

        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "statussecret"),
            displayName: "Status Secret",
            description: "A status secret test crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "lock", accentColor: "#123456"),
            paths: .init(defaultConfig: nativeConfigURL.path),
            commands: ["status": ["status", "--json"]],
            capabilities: [.status],
            statusRequiresSecrets: true,
            configOptions: [
                .init(id: "token", label: "Token", kind: .secret, envVar: "STATUS_SECRET_TOKEN", configKey: "auth.token"),
            ])
        try CrawlCoding.makeJSONEncoder().encode(manifest)
            .write(to: directory.appendingPathComponent("statussecret.json"))
        let configURL = directory.appendingPathComponent("config.json")
        let store = CrawlBarConfigStore(fileURL: configURL)
        try store.save(CrawlBarConfig(manifestDirectories: [directory.path]))
        let registry = CrawlAppRegistry(configStore: store)

        guard let plain = try registry.installation(for: manifest.id, includeSecrets: false),
              let status = try registry.installationForStatus(for: manifest.id)
        else {
            throw SelfTestError.failed("status secret crawler loads")
        }
        try Self.expect(plain.configValues["token"] == nil, "plain installation omits native secret")
        try Self.expect(status.configValues["token"] == "from-native", "status installation rehydrates native secret")
    }

    private static func testStatusMapperNormalizesCounts() throws {
        let output = """
        {"message_count":42,"channel_count":3,"last_sync_at":"2026-05-01T12:00:00Z","db_path":"/tmp/discrawl.db"}
        """
        let result = CrawlCommandResult(
            appID: BuiltInCrawlApps.discrawlID,
            action: "status",
            exitCode: 0,
            stdout: output,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())

        let status = CrawlStatusMapper().status(from: result, manifest: BuiltInCrawlApps.discrawl)
        try Self.expect(status.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 42)), "discrawl messages map")
        try Self.expect(status.lastSyncAt != nil, "whole-second last sync dates map")
        try Self.expect(status.databasePath == "/tmp/discrawl.db", "database path maps")
        try Self.expect(status.databases.first?.label == "Discord archive", "database inventory maps")
        try Self.expect(status.databases.first?.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 42)) == true, "database inventory carries counts")

        let crawlKitOutput = """
        {
          "schema_version": "crawlkit.control.v1",
          "app_id": "discrawl",
          "state": "current",
          "summary": "5052 messages across 293 channels",
          "database_path": "/tmp/discrawl.db",
          "database_bytes": 36397056,
          "counts": [
            {"id": "guilds", "label": "Guilds", "value": 56},
            {"id": "channels", "label": "Channels", "value": 293},
            {"id": "messages", "label": "Messages", "value": 5052}
          ],
          "databases": [
            {
              "id": "primary",
              "label": "Discord archive",
              "kind": "sqlite",
              "role": "archive",
              "path": "/tmp/discrawl.db",
              "is_primary": true,
              "bytes": 36397056,
              "modified_at": "2026-04-24T07:38:30Z",
              "counts": [
                {"id": "messages", "label": "Messages", "value": 5052}
              ]
            }
          ]
        }
        """
        let crawlKitResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.discrawlID,
            action: "status",
            exitCode: 0,
            stdout: crawlKitOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())

        let crawlKitStatus = CrawlStatusMapper().status(from: crawlKitResult, manifest: BuiltInCrawlApps.discrawl)
        try Self.expect(crawlKitStatus.summary == "5052 messages across 293 channels", "crawlkit status summary maps")
        try Self.expect(crawlKitStatus.state == .stale, "stale freshness wins over current state")
        try Self.expect(crawlKitStatus.databaseBytes == 36397056, "crawlkit database bytes map")
        try Self.expect(crawlKitStatus.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 5052)), "crawlkit count array maps")
        try Self.expect(crawlKitStatus.databases.first?.id == "primary", "crawlkit databases map")
        try Self.expect(crawlKitStatus.databases.first?.modifiedAt != nil, "crawlkit database modified date maps")
        try Self.expect(crawlKitStatus.databases.first?.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 5052)) == true, "crawlkit database counts map")

        let okOutput = """
        {
          "schema_version": "crawlkit.control.v1",
          "app_id": "graincrawl",
          "state": "ok",
          "summary": "1 notes",
          "counts": [{"id": "notes", "label": "Notes", "value": 1}]
        }
        """
        let okResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "status",
            exitCode: 0,
            stdout: okOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let okStatus = CrawlStatusMapper().status(from: okResult, manifest: BuiltInCrawlApps.graincrawl)
        try Self.expect(okStatus.state == .current, "crawlkit ok state maps to current")

        let failedOutput = """
        {"schema_version":"crawlkit.control.v1","app_id":"graincrawl","state":"failed","summary":"broken"}
        """
        let failedResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "status",
            exitCode: 0,
            stdout: failedOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let failedStatus = CrawlStatusMapper().status(from: failedResult, manifest: BuiltInCrawlApps.graincrawl)
        try Self.expect(failedStatus.state == .error, "crawlkit failed state maps to error")

        let githubAuthMessage = """
        [github] request GET /repos/openclaw/openclaw
        github GET /repos/openclaw/openclaw failed with status 401: {
          "message": "Bad credentials"
        }
        """
        let githubAuthResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gitcrawlID,
            action: "status",
            exitCode: 1,
            stdout: "",
            stderr: githubAuthMessage,
            startedAt: Date(),
            finishedAt: Date())
        let githubAuthStatus = CrawlStatusMapper().status(from: githubAuthResult, manifest: BuiltInCrawlApps.gitcrawl)
        try Self.expect(githubAuthStatus.state == .needsAuth, "gitcrawl 401 maps to auth state")
        try Self.expect(githubAuthStatus.summary == "GitHub credentials rejected", "gitcrawl 401 uses useful summary")
        try Self.expect(githubAuthStatus.errors == ["GitHub credentials rejected"], "gitcrawl 401 keeps request trace out of status errors")

        let githubServerMessage = """
        [github] request GET /repos/openclaw/openclaw
        github GET /repos/openclaw/openclaw failed with status 500
        """
        let githubServerStatus = CrawlAppStatus.commandFailure(
            appID: BuiltInCrawlApps.gitcrawlID,
            action: "refresh",
            message: githubServerMessage,
            fallback: "refresh failed")
        try Self.expect(
            githubServerStatus.summary == "refresh: github GET /repos/openclaw/openclaw failed with status 500",
            "gitcrawl request trace is skipped in failure summaries")
    }

    private static func testConfigValuesReachCommandEnvironment() throws {
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

    private static func testExecutableResolverUsesMacCliFallbackPaths() throws {
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
    }

    private static func testQueryActionResolverSkipsSQLForPlainText() throws {
        let sqlOnlyManifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "sqlonly"),
            displayName: "SQL Only",
            description: "A SQL-only crawler",
            binary: .init(name: "sqlonly"),
            branding: .init(symbolName: "terminal", accentColor: "#123456"),
            paths: .init(),
            commands: ["sql": ["sql"]],
            capabilities: [.search])
        try Self.expect(
            CrawlQueryActionResolver.action(for: sqlOnlyManifest, queryArguments: ["select count(*) from rows"]) == "sql",
            "SQL-looking queries can use SQL-only crawler commands")
        try Self.expect(
            CrawlQueryActionResolver.action(for: sqlOnlyManifest, queryArguments: ["manifest"]) == nil,
            "plain text queries do not fall through to SQL-only crawler commands")

        let textManifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "textcrawl"),
            displayName: "Text Crawl",
            description: "A text search crawler",
            binary: .init(name: "textcrawl"),
            branding: .init(symbolName: "terminal", accentColor: "#123456"),
            paths: .init(),
            commands: ["search": ["search"], "query": ["query"]],
            capabilities: [.search])
        try Self.expect(
            CrawlQueryActionResolver.action(for: textManifest, queryArguments: ["manifest"]) == "search",
            "plain text queries prefer explicit search commands")
    }

    private static func testGitcrawlCommandArgumentsInferRepository() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-gitcrawl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent("print-args.sh")
        try Data("""
        #!/bin/sh
        printf '%s' "$*"
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let configURL = directory.appendingPathComponent("gitcrawl.toml")
        let databaseURL = directory.appendingPathComponent("openclaw__openclaw.sync.db")
        try Data("db_path = \"\(databaseURL.path)\"\n".utf8).write(to: configURL)

        let manifest = CrawlAppManifest(
            id: BuiltInCrawlApps.gitcrawlID,
            displayName: "Git Crawl",
            description: "A git crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "tray", accentColor: "#123456"),
            paths: .init(defaultConfig: configURL.path),
            commands: ["refresh": ["sync", "--json"], "query": ["search", "--json"]],
            capabilities: [.refresh, .search])
        let installation = CrawlAppInstallation(manifest: manifest, binaryPath: scriptURL.path)

        let refreshResult = try CrawlCommandRunner().run(installation: installation, action: "refresh", timeoutSeconds: 5)
        try Self.expect(refreshResult.stdout == "sync --json openclaw/openclaw", "gitcrawl refresh infers repository")

        let queryResult = try CrawlCommandRunner().run(
            installation: installation,
            action: "query",
            extraArguments: ["stale", "branches"],
            timeoutSeconds: 5)
        try Self.expect(
            queryResult.stdout == "search --json openclaw/openclaw --query stale branches",
            "gitcrawl query infers repository and joins query text")

        let storeURL = directory.appendingPathComponent("stores/generic-store", isDirectory: true)
        let genericConfigURL = directory.appendingPathComponent("gitcrawl-generic.toml")
        let genericDatabaseURL = storeURL.appendingPathComponent("data/gitcrawl.db")
        let reportURL = storeURL.appendingPathComponent("reports/latest-status.json")
        try FileManager.default.createDirectory(
            at: genericDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("db_path = \"\(genericDatabaseURL.path)\"\n".utf8).write(to: genericConfigURL)
        try Data(#"{"repository":{"owner":"openclaw","name":"openclaw"}}"#.utf8).write(to: reportURL)
        let genericManifest = CrawlAppManifest(
            id: BuiltInCrawlApps.gitcrawlID,
            displayName: "Git Crawl",
            description: "A git crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "tray", accentColor: "#123456"),
            paths: .init(defaultConfig: genericConfigURL.path),
            commands: ["query": ["search", "--json"]],
            capabilities: [.search])
        let genericInstallation = CrawlAppInstallation(manifest: genericManifest, binaryPath: scriptURL.path)
        let genericQueryResult = try CrawlCommandRunner().run(
            installation: genericInstallation,
            action: "query",
            extraArguments: ["manifest"],
            timeoutSeconds: 5)
        try Self.expect(
            genericQueryResult.stdout == "search --json openclaw/openclaw --query manifest",
            "gitcrawl query infers repository from latest report when db filename is generic")
        let genericStatus = GitcrawlStatusSnapshot.status(for: genericInstallation)
        try Self.expect(
            genericStatus?.databasePath == genericDatabaseURL.path,
            "gitcrawl status keeps the database path that supplied its adjacent report")
        let nativeSearchManifest = CrawlAppManifest(
            id: BuiltInCrawlApps.gitcrawlID,
            displayName: "Git Crawl",
            description: "A metadata-derived git crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "tray", accentColor: "#123456"),
            paths: .init(defaultConfig: genericConfigURL.path),
            commands: ["search": ["search", "--json"]],
            capabilities: [.search])
        let nativeSearchInstallation = CrawlAppInstallation(manifest: nativeSearchManifest, binaryPath: scriptURL.path)
        let nativeSearchResult = try CrawlCommandRunner().run(
            installation: nativeSearchInstallation,
            action: "search",
            extraArguments: ["manifest"],
            timeoutSeconds: 5)
        try Self.expect(
            nativeSearchResult.stdout == "search --json openclaw/openclaw --query manifest",
            "metadata-derived gitcrawl search infers repository and query flag")

        let missingReportConfigURL = directory.appendingPathComponent("gitcrawl-missing-report.toml")
        let missingReportDatabaseURL = directory.appendingPathComponent("other-store/data/gitcrawl.db")
        try FileManager.default.createDirectory(
            at: missingReportDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("db_path = \"\(missingReportDatabaseURL.path)\"\n".utf8).write(to: missingReportConfigURL)
        let missingReportManifest = CrawlAppManifest(
            id: BuiltInCrawlApps.gitcrawlID,
            displayName: "Git Crawl",
            description: "A git crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "tray", accentColor: "#123456"),
            paths: .init(
                defaultConfig: missingReportConfigURL.path,
                defaultDatabase: directory.appendingPathComponent("wrong__repo.sync.db").path),
            commands: ["query": ["search", "--json"]],
            capabilities: [.search])
        let missingReportInstallation = CrawlAppInstallation(manifest: missingReportManifest, binaryPath: scriptURL.path)
        let missingReportQueryResult = try CrawlCommandRunner().run(
            installation: missingReportInstallation,
            action: "query",
            extraArguments: ["manifest"],
            timeoutSeconds: 5)
        try Self.expect(
            missingReportQueryResult.stdout == "search --json manifest",
            "gitcrawl query does not infer repository from unrelated global reports")
        try Self.expect(
            GitcrawlStatusSnapshot.status(for: missingReportInstallation) == nil,
            "gitcrawl status does not read unrelated global reports for explicit database configs")
    }

    private static func testActionFailuresPreserveStatusMetadata() throws {
        let lastSyncAt = Date(timeIntervalSince1970: 1_775_000_000)
        let metadata = CrawlAppStatus(
            appID: BuiltInCrawlApps.discrawlID,
            state: .current,
            summary: "5052 messages",
            configPath: "/tmp/discrawl.toml",
            databasePath: "/tmp/discrawl.db",
            databaseBytes: 36_397_056,
            lastSyncAt: lastSyncAt,
            counts: [CrawlCount(id: "messages", label: "Messages", value: 5052)],
            databases: [
                CrawlDatabaseResource(
                    id: "primary",
                    label: "Discord archive",
                    kind: .sqlite,
                    path: "/tmp/discrawl.db",
                    isPrimary: true,
                    bytes: 36_397_056),
            ],
            freshness: CrawlFreshness(status: .current, ageSeconds: 12, staleAfterSeconds: 86_400),
            share: CrawlShareStatus(enabled: true, repoPath: "/tmp/share", remote: "origin", branch: "main"),
            warnings: ["old warning"])
        let failure = CrawlAppStatus(
            appID: BuiltInCrawlApps.discrawlID,
            state: .error,
            summary: "refresh: network timed out",
            errors: ["network timed out"])

        let merged = metadata.mergingActionFailure(failure)
        try Self.expect(merged.state == .error, "action failure state is visible")
        try Self.expect(merged.summary == "refresh: network timed out", "action failure summary is visible")
        try Self.expect(merged.databasePath == metadata.databasePath, "action failure preserves database path")
        try Self.expect(merged.databases == metadata.databases, "action failure preserves databases")
        try Self.expect(merged.counts == metadata.counts, "action failure preserves counts")
        try Self.expect(merged.lastSyncAt == lastSyncAt, "action failure preserves last sync")
        try Self.expect(merged.share == metadata.share, "action failure preserves share metadata")
        try Self.expect(merged.warnings == ["old warning"], "action failure preserves existing warnings")
        try Self.expect(merged.errors == ["network timed out"], "action failure keeps failure errors")

        let githubAuthMessage = """
        [github] request GET /repos/openclaw/openclaw
        github GET /repos/openclaw/openclaw failed with status 401: {
          "message": "Bad credentials"
        }
        """
        let githubAuthFailure = CrawlAppStatus.commandFailure(
            appID: BuiltInCrawlApps.gitcrawlID,
            action: "refresh",
            message: githubAuthMessage,
            fallback: "refresh failed")
        try Self.expect(githubAuthFailure.state == .needsAuth, "gitcrawl auth failure action is recoverable")
        try Self.expect(
            githubAuthFailure.summary == "refresh: GitHub credentials rejected",
            "gitcrawl auth failure action summary is useful")

        let githubMetadata = CrawlAppStatus(
            appID: BuiltInCrawlApps.gitcrawlID,
            state: .current,
            summary: "1 repo",
            databasePath: "/tmp/gitcrawl.db",
            counts: [CrawlCount(id: "repositories", label: "Repositories", value: 1)])
        let mergedGithub = githubMetadata.mergingActionFailure(githubAuthFailure)
        try Self.expect(mergedGithub.state == .needsAuth, "action failure merge preserves auth state")
        try Self.expect(mergedGithub.summary == "refresh: GitHub credentials rejected", "action failure merge preserves auth summary")
        try Self.expect(mergedGithub.databasePath == githubMetadata.databasePath, "action failure merge preserves github metadata")

        let emptyRefreshed = CrawlAppStatus(
            appID: BuiltInCrawlApps.discrawlID,
            state: .error,
            summary: "status failed")
        let richest = CrawlAppStatus.richestMetadataStatus(emptyRefreshed, fallback: metadata)
        try Self.expect(richest == metadata, "previous rich metadata wins over empty refreshed status")

        let recoverableGraincrawlStatus = CrawlAppStatus(
            appID: BuiltInCrawlApps.graincrawlID,
            state: .error,
            summary: "private-api reports expired token, desktop-cache reports unsupported cache version 8")
        try Self.expect(
            recoverableGraincrawlStatus.isRecoverableGraincrawlSourceFailure,
            "graincrawl source status failures can render as stale")
        let graincrawlActionFailure = recoverableGraincrawlStatus.mergingActionFailure(CrawlAppStatus(
            appID: BuiltInCrawlApps.graincrawlID,
            state: .error,
            summary: "refresh: Granola access token expired",
            errors: ["Granola access token expired"]))
        try Self.expect(
            !graincrawlActionFailure.isRecoverableGraincrawlSourceFailure,
            "graincrawl action failures stay visible as errors")
    }

    private static func testActionLogStoreReadsRecentResults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-logs-\(UUID().uuidString)", isDirectory: true)
        let store = CrawlActionLogStore(directoryURL: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "refresh",
            exitCode: 1,
            stdout: "",
            stderr: "Granola access token expired",
            startedAt: Date(timeIntervalSince1970: 1_775_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_001))
        _ = try store.save(result)

        let recent = store.recentResults(limit: 5)
        try Self.expect(recent.first == result, "action logs decode back into recent command results")

        let successfulJSONResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "refresh",
            exitCode: 0,
            stdout: """
            {"notes":1}
            """,
            stderr: "",
            startedAt: Date(timeIntervalSince1970: 1_775_000_002),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_003))
        try Self.expect(successfulJSONResult.userFacingRunMessage == nil, "successful stdout is not shown as a run message")
        try Self.expect(!successfulJSONResult.shouldShowExitCode, "successful runs do not show exit code")

        let warningResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "refresh",
            exitCode: 0,
            stdout: """
            {"notes":1}
            """,
            stderr: "Used cached Granola data",
            startedAt: Date(timeIntervalSince1970: 1_775_000_004),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_005))
        try Self.expect(warningResult.userFacingRunMessage == "Used cached Granola data", "successful stderr can still surface a warning")

        let failedGitHubResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gitcrawlID,
            action: "refresh",
            exitCode: 1,
            stdout: "",
            stderr: """
            [github] request GET /repos/openclaw/openclaw
            github GET /repos/openclaw/openclaw failed with status 401: {
              "message": "Bad credentials"
            }
            """,
            startedAt: Date(timeIntervalSince1970: 1_775_000_006),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_007))
        try Self.expect(failedGitHubResult.userFacingRunMessage == "GitHub credentials rejected", "failed gitcrawl run message is normalized")

        let failedStdoutResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "refresh",
            exitCode: 1,
            stdout: "Granola refresh failed",
            stderr: "",
            startedAt: Date(timeIntervalSince1970: 1_775_000_008),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_009))
        try Self.expect(failedStdoutResult.userFacingRunMessage == "Granola refresh failed", "failed stdout is shown as a run message")
        try Self.expect(failedStdoutResult.shouldShowExitCode, "failed runs show exit code")
    }

    private static func testCommandTimeoutEscalates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent("ignore-term.sh")
        try Data("""
        #!/bin/sh
        trap '' TERM
        sleep 5
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "timeoutcrawl"),
            displayName: "Timeout Crawl",
            description: "A timeout test crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "timer", accentColor: "#123456"),
            paths: .init(),
            commands: ["status": []],
            capabilities: [.status])
        let installation = CrawlAppInstallation(manifest: manifest, binaryPath: scriptURL.path)
        let startedAt = Date()
        do {
            _ = try CrawlCommandRunner().run(installation: installation, action: "status", timeoutSeconds: 0.1)
            throw SelfTestError.failed("timeout command should not complete")
        } catch CrawlCommandRunnerError.timedOut {
            try Self.expect(Date().timeIntervalSince(startedAt) < 2.5, "timed-out commands are killed promptly")
        }
    }

    private static func testDatabaseBackupCopiesFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstDirectory = directory.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = directory.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let firstDatabaseURL = firstDirectory.appendingPathComponent("sample.db")
        let secondDatabaseURL = secondDirectory.appendingPathComponent("sample.db")
        try Self.createSQLiteDatabase(firstDatabaseURL, value: "sqlite-one")
        try Self.createSQLiteDatabase(secondDatabaseURL, value: "sqlite-two")
        let status = CrawlAppStatus(
            appID: BuiltInCrawlApps.notcrawlID,
            state: .current,
            summary: "ok",
            databases: [
                CrawlDatabaseResource(
                    id: firstDatabaseURL.path,
                    label: "Workspace One",
                    kind: .sqlite,
                    path: firstDatabaseURL.path,
                    isPrimary: true),
                CrawlDatabaseResource(
                    id: secondDatabaseURL.path,
                    label: "Workspace Two",
                    kind: .sqlite,
                    path: secondDatabaseURL.path,
                    isPrimary: false),
            ])

        let backup = try CrawlDatabaseBackupStore.backup(status: status, root: directory.appendingPathComponent("backups", isDirectory: true))
        try Self.expect(backup.files.count == 2, "backup copies duplicate-named files")
        try Self.expect(Set(backup.files.map { URL(fileURLWithPath: $0).lastPathComponent }).count == 2, "backup destination names are unique")
        let copiedContents = try backup.files.map { try Self.sqliteValue(URL(fileURLWithPath: $0)) }
        try Self.expect(copiedContents.contains("sqlite-one"), "backup preserves first duplicate file")
        try Self.expect(copiedContents.contains("sqlite-two"), "backup preserves second duplicate file")
    }

    private static func testRedactorScrubsSecrets() throws {
        let redacted = CrawlCommandRedactor().redact("""
        token=abc123
        Authorization: Bearer secret-token
        discord_token=discord-secret
        github_pat_1234567890abcdef
        ghp_1234567890abcdef
        sk-proj-1234567890abcdef
        xoxc-1234567890abcdef
        secret_notion123
        mfa.discordsecret
        label=Discord archive
        """)
        try Self.expect(!redacted.contains("abc123"), "token value redacts")
        try Self.expect(!redacted.contains("secret-token"), "bearer value redacts")
        try Self.expect(!redacted.contains("discord-secret"), "discord token value redacts")
        try Self.expect(!redacted.contains("1234567890abcdef"), "bare tokens redact")
        try Self.expect(!redacted.contains("notion123"), "notion secrets redact")
        try Self.expect(redacted.contains("Discord archive"), "discord labels are not redacted")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SelfTestError.failed(message)
        }
    }

    private static func createSQLiteDatabase(_ url: URL, value: String) throws {
        try Self.runSQLite(url, sql: "create table sample(value text); insert into sample(value) values('\(value)');")
    }

    private static func sqliteValue(_ url: URL) throws -> String {
        try Self.runSQLite(url, sql: "select value from sample limit 1;")
    }

    @discardableResult
    private static func runSQLite(_ url: URL, sql: String) throws -> String {
        guard let sqlitePath = CrawlExecutableResolver().resolve("sqlite3") else {
            throw SelfTestError.failed("sqlite3 is available")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = [url.path, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw SelfTestError.failed("sqlite3 failed: \(text)")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum SelfTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            "selftest failed: \(message)"
        }
    }
}
