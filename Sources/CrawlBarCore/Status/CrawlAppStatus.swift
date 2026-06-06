import Foundation

package struct CrawlAppStatus: Codable, Equatable, Sendable, Identifiable {
    package var schemaVersion: Int
    package var appID: CrawlAppID
    package var generatedAt: Date
    package var state: CrawlAppState
    package var summary: String
    package var configPath: String?
    package var databasePath: String?
    package var databaseBytes: Int?
    package var walBytes: Int?
    package var lastSyncAt: Date?
    package var lastImportAt: Date?
    package var lastExportAt: Date?
    package var counts: [CrawlCount]
    package var databases: [CrawlDatabaseResource]
    package var freshness: CrawlFreshness?
    package var share: CrawlShareStatus?
    package var remote: CrawlRemoteStatus?
    package var sqliteObject: CrawlSQLiteObjectStatus?
    package var sqliteBundle: CrawlSQLiteBundleStatus?
    package var warnings: [String]
    package var errors: [String]

    package var id: CrawlAppID {
        self.appID
    }

    package init(
        schemaVersion: Int = 1,
        appID: CrawlAppID,
        generatedAt: Date = Date(),
        state: CrawlAppState,
        summary: String,
        configPath: String? = nil,
        databasePath: String? = nil,
        databaseBytes: Int? = nil,
        walBytes: Int? = nil,
        lastSyncAt: Date? = nil,
        lastImportAt: Date? = nil,
        lastExportAt: Date? = nil,
        counts: [CrawlCount] = [],
        databases: [CrawlDatabaseResource] = [],
        freshness: CrawlFreshness? = nil,
        share: CrawlShareStatus? = nil,
        remote: CrawlRemoteStatus? = nil,
        sqliteObject: CrawlSQLiteObjectStatus? = nil,
        sqliteBundle: CrawlSQLiteBundleStatus? = nil,
        warnings: [String] = [],
        errors: [String] = [])
    {
        self.schemaVersion = schemaVersion
        self.appID = appID
        self.generatedAt = generatedAt
        self.state = state
        self.summary = summary
        self.configPath = configPath
        self.databasePath = databasePath
        self.databaseBytes = databaseBytes
        self.walBytes = walBytes
        self.lastSyncAt = lastSyncAt
        self.lastImportAt = lastImportAt
        self.lastExportAt = lastExportAt
        self.counts = counts
        self.databases = databases
        self.freshness = freshness
        self.share = share
        self.remote = remote
        self.sqliteObject = sqliteObject
        self.sqliteBundle = sqliteBundle
        self.warnings = warnings
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case appID = "app_id"
        case generatedAt = "generated_at"
        case state
        case summary
        case configPath = "config_path"
        case databasePath = "database_path"
        case databaseBytes = "database_bytes"
        case walBytes = "wal_bytes"
        case lastSyncAt = "last_sync_at"
        case lastImportAt = "last_import_at"
        case lastExportAt = "last_export_at"
        case counts
        case databases
        case freshness
        case share
        case remote
        case sqliteObject = "sqlite_object"
        case sqliteBundle = "sqlite_bundle"
        case warnings
        case errors
    }
}
