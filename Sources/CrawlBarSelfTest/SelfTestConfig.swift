import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testAppIDSortsByRawValue() throws {
        try Self.expect(
            [CrawlAppID(rawValue: "b"), CrawlAppID(rawValue: "a")].sorted().map(\.rawValue) == ["a", "b"],
            "app ids sort by raw value")
    }

    static func testDefaultConfigNormalizesBuiltInApps() throws {
        let config = CrawlBarConfig(apps: []).normalized()
        try Self.expect(config.version == CrawlBarConfig.currentVersion, "config version normalizes")
        try Self.expect(config.apps.map(\.id) == BuiltInCrawlApps.all.map(\.id), "built-in apps are present")
        try Self.expect(config.appConfig(for: BuiltInCrawlApps.gogcliID)?.enabled == true, "new Google app normalizes enabled")
        try Self.expect(config.appConfig(for: BuiltInCrawlApps.gogcliID)?.showInMenuBar == true, "new Google app appears in menu bar")
        try Self.expect(config.appConfig(for: BuiltInCrawlApps.photoscrawlID)?.enabled == false, "coming-soon Photos crawler normalizes disabled")
        try Self.expect(BuiltInCrawlApps.photoscrawl.availability == .comingSoon, "Photos crawler remains coming soon without an installer")
        try Self.expect(
            BuiltInCrawlApps.photoscrawl.commands["refresh"] == ["crawl", "--library", "{config:library_path}", "--json"],
            "Photos refresh uses the configured library path")
        let oldConfig = CrawlBarConfig(
            version: 1,
            apps: [CrawlBarAppConfig(id: BuiltInCrawlApps.wacliID, enabled: false, showInMenuBar: false)]).normalized()
        try Self.expect(oldConfig.appConfig(for: BuiltInCrawlApps.wacliID)?.enabled == true, "newly available apps migrate from forced disabled")
        let v2Config = CrawlBarConfig(
            version: 2,
            apps: [CrawlBarAppConfig(id: BuiltInCrawlApps.birdclawID, enabled: false, showInMenuBar: false)]).normalized()
        try Self.expect(v2Config.appConfig(for: BuiltInCrawlApps.birdclawID)?.enabled == true, "newly available Birdclaw migrates from forced disabled")
        try Self.expect(config.manifestDirectories == ["~/.crawlbar/apps"], "manifest directory default is present")
    }

    static func testConfigStoreRoundTrips() throws {
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

    static func testExternalManifestCatalog() throws {
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
        let openClawTapApps = [
            BuiltInCrawlApps.gitcrawl,
            BuiltInCrawlApps.slacrawl,
            BuiltInCrawlApps.discrawl,
            BuiltInCrawlApps.notcrawl,
            BuiltInCrawlApps.graincrawl,
        ]
        try Self.expect(
            openClawTapApps.allSatisfy { $0.install?.package.hasPrefix("openclaw/tap/") == true },
            "OpenClaw crawlers install from the current tap")
        try Self.expect(BuiltInCrawlApps.gogcli.availability == .available, "Google manifest is available")
        try Self.expect(BuiltInCrawlApps.gogcli.binary.name == "gog", "Google manifest uses the installed gog binary")
        try Self.expect(BuiltInCrawlApps.gogcli.commands["status"] == ["auth", "list", "--check", "--json", "--no-input"], "Google status is wired")
        try Self.expect(BuiltInCrawlApps.wacli.availability == .available, "WhatsApp manifest is available")
        try Self.expect(BuiltInCrawlApps.wacli.commands["status"] == ["--account", "{config:account}", "--read-only", "--json", "doctor"], "WhatsApp status is wired")
        try Self.expect(BuiltInCrawlApps.wacli.suggestion?.name == "WhatsApp", "WhatsApp manifest declares source app suggestion")
        try Self.expect(BuiltInCrawlApps.birdclaw.binary.name == "bird", "X app id uses bird executable")
        try Self.expect(BuiltInCrawlApps.telecrawl.availability == .available, "telecrawl is available")
        try Self.expect(BuiltInCrawlApps.telecrawl.commands["status"] == ["--json", "status"], "telecrawl uses JSON status command")
        try Self.expect(BuiltInCrawlApps.telecrawl.commands["refresh"] == ["--json", "import"], "telecrawl imports through refresh")
        try Self.expect(BuiltInCrawlApps.telecrawl.capabilities.contains(.search), "telecrawl advertises search")
        try Self.expect(BuiltInCrawlApps.telecrawl.privacy.containsPrivateMessages, "telecrawl privacy metadata flags Telegram messages")
        try Self.expect(BuiltInCrawlApps.telecrawl.install?.package == "steipete/tap/telecrawl", "telecrawl install metadata exists")
        try Self.expect(BuiltInCrawlApps.telecrawl.paths.defaultConfig == "~/.telecrawl/backup.json", "telecrawl config path maps")
        try Self.expect(BuiltInCrawlApps.graincrawl.availability == .available, "graincrawl is available")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.displayName == "iMessage", "imsgcrawl uses user-facing iMessage name")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.commands["status"] == ["--json", "status"], "imsgcrawl uses crawlkit status command")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.commands["refresh"] == ["--json", "sync"], "imsgcrawl sync is wired as refresh")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.commands["search"] == ["--json", "search"], "imsgcrawl search is wired")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.commands["chats"] == nil, "imsgcrawl chats stay outside persisted actions")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.commands["messages"] == nil, "imsgcrawl messages stay outside persisted actions")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.commands["contact-export"] == nil, "imsgcrawl contact export stays outside persisted actions")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.privacy.containsPrivateMessages, "imsgcrawl privacy metadata flags iMessage data")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.branding.bundleIdentifier == "com.apple.MobileSMS", "imsgcrawl uses native Messages app icon")
        try Self.expect(BuiltInCrawlApps.imsgcrawl.suggestion?.name == "Messages", "imsgcrawl suggests from the native Messages app")
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
        try Self.expect(BuiltInCrawlApps.gitcrawl.commands["remote-status"] == ["remote", "status", "--json"], "gitcrawl exposes remote status")
        try Self.expect(BuiltInCrawlApps.gitcrawl.commands["cloud-publish"] == ["cloud", "publish", "--json"], "gitcrawl exposes cloud publish")
        try Self.expect(BuiltInCrawlApps.gitcrawl.capabilities.contains(.remoteArchive), "gitcrawl advertises remote archive")
        try Self.expect(BuiltInCrawlApps.gitcrawl.capabilities.contains(.cloudPublish), "gitcrawl advertises cloud publish")
        try Self.expect(BuiltInCrawlApps.slacrawl.commands["query"] == ["sql"], "Slack exposes query action")
        try Self.expect(BuiltInCrawlApps.slacrawl.commands["search"] == ["--json", "search"], "Slack exposes text search action")
        try Self.expect(BuiltInCrawlApps.discrawl.commands["query"] == nil, "Discord does not advertise stale SQL action")
        try Self.expect(!BuiltInCrawlApps.discrawl.capabilities.contains(.search), "Discord search capability waits for upstream metadata")
        try Self.expect(BuiltInCrawlApps.discrawl.commands["remote-status"] == ["remote", "status", "--json"], "Discord exposes remote status")
        try Self.expect(BuiltInCrawlApps.discrawl.commands["cloud-publish"] == ["cloud", "publish", "--sqlite-only", "--json"], "Discord cloud publish defaults to sqlite-only")
        try Self.expect(BuiltInCrawlApps.discrawl.capabilities.contains(.remoteArchive), "Discord advertises remote archive")
        try Self.expect(BuiltInCrawlApps.discrawl.capabilities.contains(.cloudPublish), "Discord advertises cloud publish")
        try Self.expect(BuiltInCrawlApps.notcrawl.capabilities.contains(.desktopCache), "Notion advertises desktop cache capability")
        try Self.expect(BuiltInCrawlApps.gitcrawl.configSections.contains { $0.id == "github" }, "built-in config sections exist")
    }

    static func testNativeConfigRoundTrips() throws {
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

    static func testStatusSecretsLoadFromNativeConfig() throws {
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
}
