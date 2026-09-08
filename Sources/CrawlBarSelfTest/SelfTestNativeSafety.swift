import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testNativeArchiveMappingAndBackupSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crawlbar-source-safety-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.db")
        let archive = directory.appendingPathComponent("archive.db")
        try Data("synthetic source".utf8).write(to: source)
        try Data("synthetic archive".utf8).write(to: archive)
        let payload: [String: Any] = [
            "schema_version": "crawlkit.control.v1", "state": "ok",
            "source": ["database_path": source.path, "database_bytes": 999],
            "archive": ["archive_path": archive.path, "archive_bytes": 17],
        ]
        let status = CrawlStatusMapper().status(
            from: try Self.nativeStatusResult(payload, appID: BuiltInCrawlApps.imsgcrawlID),
            manifest: BuiltInCrawlApps.imsgcrawl)
        try Self.expect(status.databasePath == archive.path, "imsg archive path wins over source database_path")
        try Self.expect(status.databaseBytes == 17, "imsg archive byte count is not the source count")
        try Self.expect(status.databases.count == 1 && status.databases[0].path == archive.path, "inventory contains only the archive")

        let capture = directory.appendingPathComponent("backup-source.txt")
        let sqlite = directory.appendingPathComponent("sqlite3")
        let quoted = "'" + capture.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        try Data("#!/bin/sh\nprintf '%s' \"$1\" > \(quoted)\ncat >/dev/null\n".utf8).write(to: sqlite)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sqlite.path)
        let resolver = CrawlExecutableResolver(environment: ["HOME": directory.path, "PATH": directory.path + ":/usr/bin:/bin"])
        let backup = try CrawlDatabaseBackupStore.backup(
            status: status, root: directory.appendingPathComponent("backups"),
            resolver: resolver, sqliteProcessTimeout: 5)
        try Self.expect(backup.files.count == 1, "backup selects one archive resource")
        let selected = try String(contentsOf: capture, encoding: .utf8)
        try Self.expect(selected == archive.path, "actual backup invocation never receives the source database")
        let sourceBytes = try Data(contentsOf: source)
        try Self.expect(sourceBytes == Data("synthetic source".utf8), "source bytes remain unchanged")
        let missingArchivePayloads: [[String: Any]] = [
            ["database_path": source.path],
            ["db_path": source.path, "databases": [["id": "source", "kind": "sqlite", "path": source.path]]],
            ["source": ["database_path": source.path], "archive": [:]],
        ]
        for missing in missingArchivePayloads {
            let mapped = CrawlStatusMapper().status(
                from: try Self.nativeStatusResult(missing, appID: BuiltInCrawlApps.imsgcrawlID),
                manifest: BuiltInCrawlApps.imsgcrawl)
            try Self.expect(mapped.databasePath == nil && mapped.databases.isEmpty, "missing imsg archive_path cannot infer any backup resource")
        }
    }

    static func testNativeStatusFreshnessAndMissingState() throws {
        let manifest = Self.nativeFixtureManifest(commands: ["status": ["status"]])
        let old: [String: Any] = [
            "schema_version": "crawlkit.control.v1", "state": "ready",
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "last_import_at": "2000-01-01T00:00:00Z",
        ]
        let status = CrawlStatusMapper().status(
            from: try Self.nativeStatusResult(old, appID: manifest.id), manifest: manifest, staleAfterSeconds: 60)
        try Self.expect(status.state == .current, "explicit readiness remains separate from freshness")
        try Self.expect(status.freshness?.status == .stale, "fresh status output cannot refresh old imported data")
        try Self.expect(status.lastSyncAt == nil && status.lastImportAt != nil, "import is not mislabeled as a sync")
        let never = CrawlStatusMapper().status(
            from: try Self.nativeStatusResult(["state": "ready", "generated_at": "2026-09-08T12:00:00Z"], appID: manifest.id),
            manifest: manifest)
        try Self.expect(never.lastSyncAt == nil && never.freshness == nil, "generated_at alone establishes no data freshness")
        for (raw, expected) in [("missing", CrawlAppState.needsConfig), ("unrecognized-state", .unknown), ("ready", .current)] {
            let mapped = CrawlStatusMapper().status(
                from: try Self.nativeStatusResult(["state": raw], appID: manifest.id), manifest: manifest)
            try Self.expect(mapped.state == expected, "external manifest state \(raw) maps truthfully")
        }
    }

    static func testNativeRecursiveConfigExpansion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crawlbar-config-safety-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var manifest = Self.nativeFixtureManifest(commands: ["status": ["%s", "{config:first}"]], binary: "/usr/bin/printf")
        manifest.configOptions = [.init(id: "third", label: "Third", defaultValue: "value")]
        let runner = CrawlCommandRunner(environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"])
        let installation = CrawlAppInstallation(manifest: manifest, binaryPath: "/usr/bin/printf")
        let nested = try runner.run(
            installation: installation,
            configValues: ["first": "prefix-{config:second}", "second": "{config:third}"],
            action: "status", timeoutSeconds: 5)
        try Self.expect(nested.stdout == "prefix-value", "finite acyclic recursive interpolation is preserved")
        let accountManifest = Self.nativeFixtureManifest(commands: ["status": ["%s", "--account", "{config:account}", "value"]])
        let account = try runner.run(
            installation: .init(manifest: accountManifest, binaryPath: "/usr/bin/printf"),
            configValues: [:], action: "status", timeoutSeconds: 5)
        try Self.expect(account.stdout == "value", "an omitted optional account retains existing argv behavior")
        for values in [
            ["first": "{config:first}"],
            ["first": "{config:second}", "second": "{config:first}"],
            ["first": "{config:first}x"],
            ["first": String(repeating: "x", count: 1_048_577)],
        ] {
            do {
                _ = try runner.run(installation: installation, configValues: values, action: "status", timeoutSeconds: 5)
                throw SelfTestError.failed("unbounded config expansion accepted")
            } catch CrawlCommandRunnerError.invalidConfigExpansion {
            }
        }
    }

    static func testExistingCredentialFixOnFailureLogs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crawlbar-existing-redaction-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("fixture")
        try Data("#!/bin/sh\nprintf '%s' \"$CRAWLBAR_FIXTURE_SECRET\"\nprintf '%s' \"$CRAWLBAR_FIXTURE_SECRET\" >&2\nexit 7\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var manifest = Self.nativeFixtureManifest(commands: ["status": []], binary: script.path)
        manifest.configOptions = [.init(id: "fixture", label: "Fixture", kind: .secret, envVar: "CRAWLBAR_FIXTURE_SECRET")]
        let installation = CrawlAppInstallation(manifest: manifest, binaryPath: script.path)
        let synthetic = "opaque-" + UUID().uuidString
        let result = try CrawlCommandRunner(environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"]).run(
            installation: installation, configValues: ["fixture": synthetic], action: "status", timeoutSeconds: 5)
        try Self.expect(result.exitCode == 7 && result.stdout == "[REDACTED]" && result.stderr == "[REDACTED]", "existing exact-value redaction covers both failure streams")
        let log = try CrawlActionLogStore(directoryURL: directory.appendingPathComponent("logs")).save(result)
        let persisted = try String(contentsOf: log, encoding: .utf8)
        try Self.expect(!persisted.contains(synthetic) && installation.configValues.isEmpty, "existing credential fix keeps installation and persisted result secret-free")
    }

    static func nativeFixtureManifest(commands: [String: [String]], binary: String = "/usr/bin/printf") -> CrawlAppManifest {
        CrawlAppManifest(
            id: CrawlAppID(rawValue: "native-fixture"), displayName: "Native Fixture",
            description: "Synthetic control fixture", binary: .init(name: binary),
            branding: .init(symbolName: "terminal", accentColor: "#123456"),
            paths: .init(), commands: commands, capabilities: [.status])
    }

    static func nativeStatusResult(_ payload: [String: Any], appID: CrawlAppID) throws -> CrawlCommandResult {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return CrawlCommandResult(
            appID: appID, action: "status", exitCode: 0,
            stdout: String(decoding: data, as: UTF8.self), stderr: "",
            startedAt: Date(), finishedAt: Date())
    }
}
