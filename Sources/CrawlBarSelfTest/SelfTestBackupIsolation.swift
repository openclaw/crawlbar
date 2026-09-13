import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testBackupIsolation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-backup-isolation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("backups", isDirectory: true)
        let firstSource = directory.appendingPathComponent("first.db")
        try Self.createSQLiteDatabase(firstSource, value: "original")
        let resource = CrawlDatabaseResource(id: "first", label: "First", kind: .sqlite, path: firstSource.path)
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        func backup(_ id: String, _ resources: [CrawlDatabaseResource]) throws -> CrawlDatabaseBackup {
            try CrawlDatabaseBackupStore.backup(
                status: CrawlAppStatus(appID: CrawlAppID(rawValue: id), state: .current, summary: "Fixture", databases: resources),
                root: root, resolver: CrawlExecutableResolver(), sqliteProcessTimeout: 5, now: now)
        }

        let first = try backup("repeated", [resource])
        try Self.runSQLite(firstSource, sql: "update sample set value = 'updated';")
        let second = try backup("repeated", [resource])
        try Self.expect(first.directory != second.directory, "backups at the same instant have separate directories")
        try Self.expect(try Self.sqliteValue(URL(fileURLWithPath: first.files[0])) == "original", "later backups preserve earlier snapshots")
        try Self.expect(try Self.sqliteValue(URL(fileURLWithPath: second.files[0])) == "updated", "new backups contain current source data")

        for id in ["../escaped", "..", "/absolute", "", "percent%/id"] {
            let result = try backup(id, [resource])
            let path = URL(fileURLWithPath: result.directory).standardizedFileURL.path
            try Self.expect(path.hasPrefix(root.standardizedFileURL.path + "/"), "crawler identifiers cannot escape the backup root")
            let directoryAttributes = try FileManager.default.attributesOfItem(atPath: result.directory)
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: result.files[0])
            try Self.expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "backup directories are private")
            try Self.expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "backup files are private")
        }

        let upperDirectory = directory.appendingPathComponent("upper", isDirectory: true)
        let lowerDirectory = directory.appendingPathComponent("lower", isDirectory: true)
        try FileManager.default.createDirectory(at: upperDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lowerDirectory, withIntermediateDirectories: true)
        let upper = upperDirectory.appendingPathComponent("Archive.db")
        let lower = lowerDirectory.appendingPathComponent("archive.db")
        try Self.createSQLiteDatabase(upper, value: "upper")
        try Self.createSQLiteDatabase(lower, value: "lower")
        let caseResult = try backup("case", [
            CrawlDatabaseResource(id: "upper", label: "Upper", kind: .sqlite, path: upper.path),
            CrawlDatabaseResource(id: "lower", label: "Lower", kind: .sqlite, path: lower.path),
        ])
        let caseValues = try caseResult.files.map { try Self.sqliteValue(URL(fileURLWithPath: $0)) }
        try Self.expect(caseValues == ["upper", "lower"], "case-only names preserve both archives on the destination filesystem")

        let invalid = directory.appendingPathComponent("invalid.db")
        try Data("not a SQLite database".utf8).write(to: invalid)
        do {
            _ = try backup("repeated", [resource, CrawlDatabaseResource(id: "bad", label: "Bad", kind: .sqlite, path: invalid.path)])
            throw SelfTestError.failed("invalid SQLite input must fail backup")
        } catch CrawlDatabaseBackupError.sqliteBackupFailed {
            let remaining = try FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("repeated"), includingPropertiesForKeys: nil)
            let remainingPaths = Set(remaining.map { $0.resolvingSymlinksInPath().path })
            let completedPaths = Set([first.directory, second.directory].map {
                URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
            })
            try Self.expect(remainingPaths == completedPaths, "failed backups remove only their partial directory")
            try Self.expect(try Self.sqliteValue(URL(fileURLWithPath: first.files[0])) == "original", "failed backups preserve completed snapshots")
        }
    }
}
