import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testQueryActionResolverSkipsSQLForPlainText() throws {
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

    static func testWacliSearchJoinsQueryArguments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-wacli-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent("wacli")
        try Data("""
        #!/bin/sh
        printf '%s\\n' "$#"
        for arg in "$@"; do printf '<%s>\\n' "$arg"; done
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = CrawlAppManifest(
            id: BuiltInCrawlApps.wacliID,
            displayName: "WhatsApp",
            description: "A WhatsApp crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "message", accentColor: "#25D366"),
            paths: .init(),
            commands: ["search": ["messages", "search"]],
            capabilities: [.search])
        let installation = CrawlAppInstallation(manifest: manifest, binaryPath: scriptURL.path)
        let result = try CrawlCommandRunner()
            .run(installation: installation, action: "search", extraArguments: ["hello", "world"], timeoutSeconds: 5)

        try Self.expect(
            result.stdout == "3\n<messages>\n<search>\n<hello world>\n",
            "wacli search receives multi-word query as one argument")

        let flaggedResult = try CrawlCommandRunner()
            .run(
                installation: installation,
                action: "search",
                extraArguments: ["hello", "world", "--limit", "5"],
                timeoutSeconds: 5)
        try Self.expect(
            flaggedResult.stdout == "5\n<messages>\n<search>\n<hello world>\n<--limit>\n<5>\n",
            "wacli search preserves flags after joined query")

        let builtInDefault = CrawlAppInstallation(manifest: BuiltInCrawlApps.wacli, binaryPath: scriptURL.path)
        let defaultAccountResult = try CrawlCommandRunner()
            .run(installation: builtInDefault, action: "search", extraArguments: ["hello", "world"], timeoutSeconds: 5)
        try Self.expect(
            defaultAccountResult.stdout == "5\n<--read-only>\n<--json>\n<messages>\n<search>\n<hello world>\n",
            "built-in wacli omits account flag until configured")

        let builtInNamed = CrawlAppInstallation(
            manifest: BuiltInCrawlApps.wacli,
            binaryPath: scriptURL.path,
            configValues: ["account": "personal"])
        let namedAccountResult = try CrawlCommandRunner()
            .run(installation: builtInNamed, action: "search", extraArguments: ["hello", "world"], timeoutSeconds: 5)
        try Self.expect(
            namedAccountResult.stdout == "7\n<--account>\n<personal>\n<--read-only>\n<--json>\n<messages>\n<search>\n<hello world>\n",
            "built-in wacli applies configured account")

        let literalConfigQuery = try CrawlCommandRunner()
            .run(
                installation: builtInNamed,
                action: "search",
                extraArguments: ["{config:account}"],
                timeoutSeconds: 5)
        try Self.expect(
            literalConfigQuery.stdout == "7\n<--account>\n<personal>\n<--read-only>\n<--json>\n<messages>\n<search>\n<{config:account}>\n",
            "user query text is not config-interpolated")
    }

    static func testGitcrawlCommandArgumentsInferRepository() throws {
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
}
