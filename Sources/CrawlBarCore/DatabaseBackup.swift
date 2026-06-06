import Foundation

public struct CrawlDatabaseBackup: Codable, Equatable, Sendable {
    public var appID: CrawlAppID
    public var directory: String
    public var files: [String]
    public var createdAt: Date

    public init(appID: CrawlAppID, directory: String, files: [String], createdAt: Date = Date()) {
        self.appID = appID
        self.directory = directory
        self.files = files
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case directory
        case files
        case createdAt = "created_at"
    }
}

public enum CrawlDatabaseBackupError: LocalizedError, Sendable {
    case noDatabases(CrawlAppID)
    case sqliteUnavailable
    case sqliteBackupFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case let .noDatabases(appID):
            "\(appID.rawValue) does not expose any local database files to back up"
        case .sqliteUnavailable:
            "sqlite3 is not available on PATH"
        case let .sqliteBackupFailed(path, message):
            "SQLite backup failed for \(path): \(message)"
        }
    }
}

public enum CrawlDatabaseBackupStore {
    public static func defaultDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".crawlbar", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
    }

    public static func backup(status: CrawlAppStatus, root: URL = Self.defaultDirectory()) throws -> CrawlDatabaseBackup {
        let resources = status.databases
            .filter { $0.kind == .sqlite || $0.kind == .cache }
            .compactMap { resource -> (resource: CrawlDatabaseResource, source: URL)? in
                guard let path = resource.path?.nilIfBlank else { return nil }
                let source = URL(fileURLWithPath: PathExpander.expandHome(path))
                guard FileManager.default.fileExists(atPath: source.path) else { return nil }
                return (resource, source)
            }

        guard !resources.isEmpty else {
            throw CrawlDatabaseBackupError.noDatabases(status.appID)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let directory = root
            .appendingPathComponent(status.appID.rawValue, isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var copied: [String] = []
        var usedNames: Set<String> = []
        let basenameCounts = Dictionary(grouping: resources, by: { $0.source.lastPathComponent })
            .mapValues(\.count)
        for entry in resources {
            let destinationName = Self.destinationName(
                for: entry.resource,
                source: entry.source,
                basenameCounts: basenameCounts,
                usedNames: &usedNames)
            let destination = directory.appendingPathComponent(destinationName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            if entry.resource.kind == .sqlite || entry.resource.kind == .cache {
                try Self.backupSQLite(source: entry.source, destination: destination)
            } else {
                try FileManager.default.copyItem(at: entry.source, to: destination)
            }
            copied.append(destination.path)
        }

        return CrawlDatabaseBackup(appID: status.appID, directory: directory.path, files: copied)
    }

    private static func backupSQLite(source: URL, destination: URL) throws {
        guard let sqlitePath = CrawlExecutableResolver().resolve("sqlite3") else {
            throw CrawlDatabaseBackupError.sqliteUnavailable
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = [source.path]

        let input = Pipe()
        let pipe = Pipe()
        process.standardInput = input
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let command = ".timeout 5000\n.backup '\(destination.path.replacingOccurrences(of: "'", with: "''"))'\n"
        input.fileHandleForWriting.write(Data(command.utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.nilIfBlank ?? "sqlite3 exited \(process.terminationStatus)"
            throw CrawlDatabaseBackupError.sqliteBackupFailed(path: source.path, message: message)
        }
    }

    private static func destinationName(
        for resource: CrawlDatabaseResource,
        source: URL,
        basenameCounts: [String: Int],
        usedNames: inout Set<String>)
        -> String
    {
        let basename = source.lastPathComponent
        let shouldPrefix = (basenameCounts[basename] ?? 0) > 1
        let prefix = Self.safeFilename(resource.label.nilIfBlank ?? resource.id)
        var candidate = shouldPrefix ? "\(prefix)-\(basename)" : basename
        var suffix = 2
        while usedNames.contains(candidate) {
            candidate = "\(prefix)-\(suffix)-\(basename)"
            suffix += 1
        }
        usedNames.insert(candidate)
        return candidate
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.nilIfBlank ?? "database"
    }
}
