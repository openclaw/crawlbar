import CrawlBarCore
import Darwin
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

        let duplicateTimestampResult = CrawlCommandResult(
            appID: result.appID,
            action: result.action,
            exitCode: 0,
            stdout: "second",
            stderr: "",
            startedAt: result.startedAt,
            finishedAt: result.finishedAt)
        _ = try store.save(duplicateTimestampResult)
        let duplicateTimestampLogs = store.recentResults(limit: 5)
        try Self.expect(duplicateTimestampLogs.contains(result), "duplicate action timestamps preserve the first log")
        try Self.expect(duplicateTimestampLogs.contains(duplicateTimestampResult), "duplicate action timestamps preserve the second log")

        let unsafeResult = CrawlCommandResult(
            appID: CrawlAppID(rawValue: "../unsafe/app"),
            action: "../refresh:now",
            exitCode: 0,
            stdout: "",
            stderr: "",
            startedAt: Date(timeIntervalSince1970: 1_775_000_001),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_001))
        let unsafeURL = try store.save(unsafeResult)
        try Self.expect(
            unsafeURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
            "unsafe action log identifiers stay inside the log directory")
        try Self.expect(
            !unsafeURL.lastPathComponent.contains("unsafe") && !unsafeURL.lastPathComponent.contains("refresh"),
            "action log filenames do not expose command identifiers")

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

    static func testActionLogStorePrunesOldLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-log-cap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CrawlActionLogStore(directoryURL: directory)
        let cap = 200
        let total = cap + 3
        for index in 0..<total {
            let url = directory.appendingPathComponent(String(format: "old-%04d.json", index))
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))],
                ofItemAtPath: url.path)
        }
        try Data("keep".utf8).write(to: directory.appendingPathComponent("readme.txt"))
        let preservedDirectory = directory.appendingPathComponent("archive.json", isDirectory: true)
        try FileManager.default.createDirectory(at: preservedDirectory, withIntermediateDirectories: true)
        let preservedFile = preservedDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: preservedFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: preservedDirectory.path)
        let preservedLink = directory.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: preservedLink, withDestinationURL: preservedDirectory)

        let listed = store.recent(limit: 5)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        try Self.expect(FileManager.default.fileExists(atPath: preservedFile.path), "log retention preserves JSON-named directories and their contents")
        try Self.expect(names.contains("linked.json"), "log retention preserves symlinks")
        let jsonNames = names.filter { $0.hasPrefix("old-") && $0.hasSuffix(".json") }
        try Self.expect(jsonNames.count == cap, "listing action logs drops files past the retention cap")
        try Self.expect(names.contains("readme.txt"), "log retention leaves non-json files alone")
        try Self.expect(!jsonNames.contains("old-0000.json"), "listing action logs removes the oldest file")
        try Self.expect(
            jsonNames.contains(String(format: "old-%04d.json", total - 1)),
            "listing action logs keeps the newest file")
        try Self.expect(listed.count == 5, "recent action logs still honor the requested limit")
        try Self.expect(
            listed.first?.lastPathComponent == String(format: "old-%04d.json", total - 1),
            "recent action logs stay ordered newest first")

        let saved = try store.save(CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "refresh",
            exitCode: 0,
            stdout: "capped",
            stderr: "",
            startedAt: Date(timeIntervalSince1970: 1_775_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_001)))
        let afterSave = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let jsonAfterSave = afterSave.filter { $0.hasSuffix(".json") && $0 != "archive.json" && $0 != "linked.json" }
        try Self.expect(jsonAfterSave.count == cap, "saving an action log keeps the directory at the cap")
        try Self.expect(jsonAfterSave.contains(saved.lastPathComponent), "saving an action log keeps the new file")
        try Self.expect(!jsonAfterSave.contains("old-0003.json"), "saving an action log removes the next oldest file")
        try Self.expect(afterSave.contains("readme.txt"), "saving an action log leaves non-json files alone")
        try Self.expect(FileManager.default.fileExists(atPath: preservedFile.path), "saving preserves JSON-named directory contents")
        try Self.expect(afterSave.contains("linked.json"), "saving preserves symlinks")
        let allLogs = store.recent(limit: 300)
        try Self.expect(allLogs.count == cap, "retention caps requests larger than the log limit")
        try Self.expect(!allLogs.contains(preservedDirectory) && !allLogs.contains(preservedLink), "recent logs exclude directories and symlinks")
        try Self.expect(store.recent(limit: 0).isEmpty, "zero recent logs returns no results")
        try Self.expect(store.recent(limit: -1).isEmpty, "negative recent logs returns no results")
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

    static func testProcessWaitTimesOut() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; exec /bin/sleep 3"]
        try process.run()
        let pid = process.processIdentifier
        let startedAt = Date()
        let outcome = CrawlProcessWait.waitUntilExit(process, timeoutSeconds: 0.2)
        try Self.expect(outcome == .timedOut, "wedged child wait returns timedOut instead of blocking")
        try Self.expect(Date().timeIntervalSince(startedAt) < 2.5, "timed-out child is killed promptly")
        try Self.expect(!process.isRunning, "timed-out child is reaped")
        errno = 0
        try Self.expect(kill(pid, 0) == -1 && errno == ESRCH, "timed-out child pid is gone")
    }

    static func testInstallerTimesOutWedgedBrew() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-install-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let brew = directory.appendingPathComponent("brew")
        try Data("""
        #!/bin/sh
        trap '' TERM
        exec /bin/sleep 5
        """.utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(directory.path):\(environment["PATH"] ?? "")"
        let installer = CrawlInstaller(
            resolver: CrawlExecutableResolver(environment: environment),
            environment: environment)
        let manifest = CrawlAppManifest(
            id: CrawlAppID(rawValue: "installtimeout"),
            displayName: "Install Timeout",
            description: "A timeout test installer",
            binary: .init(name: "installtimeout"),
            branding: .init(symbolName: "timer", accentColor: "#123456"),
            paths: .init(),
            commands: [:],
            capabilities: [],
            install: .init(method: .homebrew, package: "installtimeout"))
        let startedAt = Date()
        do {
            _ = try installer.install(CrawlAppInstallation(manifest: manifest), timeoutSeconds: 0.1)
            throw SelfTestError.failed("wedged brew install should time out")
        } catch CrawlCommandRunnerError.timedOut {
            try Self.expect(Date().timeIntervalSince(startedAt) < 2.5, "install timeout kills brew promptly")
        }
    }

    static func testTimeoutTeardownUsesProcessWait() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CrawlBarCore")
        for name in ["CrawlCommandRunnerProcess.swift", "Installer.swift"] {
            let text = try String(contentsOf: core.appendingPathComponent(name), encoding: .utf8)
            try Self.expect(
                text.contains(name == "Installer.swift" ? "runner.runProcess(" : "CrawlProcessWait.waitUntilExit"),
                "\(name) uses the shared bounded process runner")
            try Self.expect(
                !text.contains("process.waitUntilExit()"),
                "\(name) does not call unbounded Process.waitUntilExit")
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

    static func testDatabaseBackupTimesOutWedgedSqlite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-backup-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let sqlite3 = bin.appendingPathComponent("sqlite3")
        try Data("""
        #!/bin/sh
        trap '' TERM
        exec /bin/sleep 5
        """.utf8).write(to: sqlite3)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sqlite3.path)

        let source = directory.appendingPathComponent("hang.db")
        try Data().write(to: source)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(bin.path):\(environment["PATH"] ?? "")"
        let resolver = CrawlExecutableResolver(environment: environment)
        let status = CrawlAppStatus(
            appID: BuiltInCrawlApps.notcrawlID,
            state: .current,
            summary: "ok",
            databases: [
                CrawlDatabaseResource(
                    id: source.path,
                    label: "Hang",
                    kind: .sqlite,
                    path: source.path,
                    isPrimary: true),
            ])

        let startedAt = Date()
        do {
            _ = try CrawlDatabaseBackupStore.backup(
                status: status,
                root: directory.appendingPathComponent("backups", isDirectory: true),
                resolver: resolver,
                sqliteProcessTimeout: 0.2)
            throw SelfTestError.failed("wedged sqlite3 backup should time out")
        } catch CrawlDatabaseBackupError.timedOut {
            try Self.expect(Date().timeIntervalSince(startedAt) < 2.5, "backup timeout kills sqlite3 promptly")
        }
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
