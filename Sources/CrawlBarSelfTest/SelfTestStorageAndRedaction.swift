import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testActionLogStoreReadsRecentResults() throws {
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

        let failedBirdResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.birdclawID,
            action: "status",
            exitCode: 1,
            stdout: "",
            stderr: "Missing auth_token",
            startedAt: Date(timeIntervalSince1970: 1_775_000_006),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_007))
        try Self.expect(failedBirdResult.userFacingRunMessage == "X browser cookies not found", "failed X credential check maps to auth setup")

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

    static func testCommandTimeoutEscalates() throws {
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

    static func testDatabaseBackupCopiesFiles() throws {
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

    static func testRedactorScrubsSecrets() throws {
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
        ct0: csrf-secret
        label=Discord archive
        """)
        try Self.expect(!redacted.contains("abc123"), "token value redacts")
        try Self.expect(!redacted.contains("secret-token"), "bearer value redacts")
        try Self.expect(!redacted.contains("discord-secret"), "discord token value redacts")
        try Self.expect(!redacted.contains("1234567890abcdef"), "bare tokens redact")
        try Self.expect(!redacted.contains("notion123"), "notion secrets redact")
        try Self.expect(!redacted.contains("csrf-secret"), "ct0 cookies redact")
        try Self.expect(redacted.contains("Discord archive"), "discord labels are not redacted")
    }
}
