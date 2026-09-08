import Foundation

extension CrawlStatusMapper {
    func genericStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let counts = self.statusCounts(in: object, fallback: self.counts(in: object))
        let imsgArchive = (object["archive"] as? [String: Any]) ?? object
        let isImsg = result.appID == BuiltInCrawlApps.imsgcrawlID
        // The iMessage envelope also contains a source database_path. Never
        // expose that source as an archive resource: backup selects all SQLite rows.
        let databasePath = isImsg
            ? (imsgArchive["archive_path"] as? String)?.nilIfBlank
            : self.stringValue(["db_path", "database_path"], in: object)
        let databases = self.databaseResources(in: object).filter {
            !isImsg || ($0.path != nil && $0.path == databasePath)
        }
        let remote = self.remoteStatus(in: object)
        let lastImportAt = self.dateValue(["last_import_at"], in: object)
        let lastSyncAt = self.dateValue(["last_sync_at"], in: object)
            ?? remote?.lastSyncAt
            ?? remote?.lastIngestAt
        let observedDataAt = lastSyncAt ?? lastImportAt
            ?? remote?.lastSyncAt
            ?? remote?.lastIngestAt
        let freshness = self.freshness(in: object, lastSyncAt: observedDataAt, staleAfterSeconds: staleAfterSeconds)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.statusState(in: object, lastSyncAt: observedDataAt, freshness: freshness, fallback: .current, staleAfterSeconds: staleAfterSeconds),
            summary: self.stringValue(["summary", "message"], in: object) ?? self.summary(from: counts, fallback: "Status received"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: databasePath,
            databaseBytes: isImsg
                ? self.intValue(["archive_bytes"], in: imsgArchive)
                : self.intValue(["db_bytes", "database_bytes"], in: object),
            walBytes: self.intValue(["wal_bytes"], in: object),
            lastSyncAt: lastSyncAt,
            lastImportAt: lastImportAt,
            lastExportAt: self.dateValue(["last_export_at"], in: object),
            counts: counts,
            databases: databases,
            freshness: freshness,
            share: self.shareStatus(in: object),
            remote: remote,
            sqliteObject: self.sqliteObjectStatus(in: object),
            sqliteBundle: self.sqliteBundleStatus(in: object),
            warnings: self.stringValues(["warnings"], in: object),
            errors: self.stringValues(["errors"], in: object))
    }

    func isCrawlKitStatus(_ object: [String: Any]) -> Bool {
        if let schema = self.stringValue(["schema_version"], in: object), schema.hasPrefix("crawlkit.control.") {
            return true
        }
        return self.firstValue("databases", in: object) != nil && self.firstValue("counts", in: object) != nil
    }
}
