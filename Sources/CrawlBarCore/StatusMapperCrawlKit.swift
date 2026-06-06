import Foundation

extension CrawlStatusMapper {
    func genericStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let counts = self.statusCounts(in: object, fallback: self.counts(in: object))
        let databases = self.databaseResources(in: object)
        let remote = self.remoteStatus(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "updated_at", "generated_at"], in: object)
            ?? remote?.lastSyncAt
            ?? remote?.lastIngestAt
            ?? self.databaseModifiedAt(databases)
        let freshness = self.freshness(in: object, lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.statusState(in: object, lastSyncAt: lastSyncAt, freshness: freshness, fallback: .current, staleAfterSeconds: staleAfterSeconds),
            summary: self.stringValue(["summary", "message"], in: object) ?? self.summary(from: counts, fallback: "Status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path"], in: object),
            databaseBytes: self.intValue(["db_bytes", "database_bytes"], in: object),
            walBytes: self.intValue(["wal_bytes"], in: object),
            lastSyncAt: lastSyncAt,
            lastImportAt: self.dateValue(["last_import_at"], in: object),
            lastExportAt: self.dateValue(["last_export_at"], in: object),
            counts: counts,
            databases: databases,
            freshness: freshness,
            share: self.shareStatus(in: object),
            remote: remote,
            sqliteObject: self.sqliteObjectStatus(in: object),
            sqliteBundle: self.sqliteBundleStatus(in: object))
    }

    func isCrawlKitStatus(_ object: [String: Any]) -> Bool {
        if let schema = self.stringValue(["schema_version"], in: object), schema.hasPrefix("crawlkit.control.") {
            return true
        }
        return self.firstValue("databases", in: object) != nil && self.firstValue("counts", in: object) != nil
    }
}
