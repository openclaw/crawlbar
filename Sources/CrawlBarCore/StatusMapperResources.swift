import Foundation

extension CrawlStatusMapper {
    func count(_ id: String, _ label: String, _ keys: [String]) -> (String, String, [String]) {
        (id, label, keys)
    }

    func value(_ spec: (String, String, [String]), in object: [String: Any]) -> CrawlCount? {
        guard let value = self.intValue(spec.2, in: object) else { return nil }
        return CrawlCount(id: spec.0, label: spec.1, value: value)
    }

    func counts(in object: [String: Any]) -> [CrawlCount] {
        guard let counts = self.firstObject(["counts", "stats"], in: object) else { return [] }
        return counts.compactMap { key, value in
            guard let int = self.int(value) else { return nil }
            return CrawlCount(id: key, label: self.label(from: key), value: int)
        }
        .sorted { $0.id < $1.id }
    }

    func state(lastSyncAt: Date?, fallback: CrawlAppState, staleAfterSeconds: Int?) -> CrawlAppState {
        guard let lastSyncAt else { return fallback }
        let threshold = staleAfterSeconds ?? Self.defaultStaleAfterSeconds
        return Date().timeIntervalSince(lastSyncAt) > TimeInterval(threshold) ? .stale : .current
    }

    func freshness(lastSyncAt: Date?, staleAfterSeconds: Int?) -> CrawlFreshness? {
        guard let lastSyncAt else { return nil }
        let threshold = staleAfterSeconds ?? Self.defaultStaleAfterSeconds
        let ageSeconds = max(0, Int(Date().timeIntervalSince(lastSyncAt)))
        return CrawlFreshness(
            status: ageSeconds > threshold ? .stale : .current,
            ageSeconds: ageSeconds,
            staleAfterSeconds: threshold)
    }

    func freshness(in object: [String: Any], lastSyncAt: Date?, staleAfterSeconds: Int?) -> CrawlFreshness? {
        if let freshness = self.firstObject(["freshness"], in: object),
           let status = self.statusValue(["status", "state"], in: freshness)
        {
            return CrawlFreshness(
                status: status,
                ageSeconds: self.intValue(["age_seconds"], in: freshness),
                staleAfterSeconds: self.intValue(["stale_after_seconds"], in: freshness) ?? staleAfterSeconds)
        }
        return self.freshness(lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds)
    }

    func summary(from counts: [CrawlCount], fallback: String) -> String {
        let visible = counts.prefix(2).map { "\($0.value) \($0.label.lowercased())" }
        return visible.isEmpty ? fallback : visible.joined(separator: ", ")
    }

    func statusState(
        in object: [String: Any],
        lastSyncAt: Date?,
        freshness: CrawlFreshness?,
        fallback: CrawlAppState,
        staleAfterSeconds: Int?)
        -> CrawlAppState
    {
        if let state = self.statusValue(["state", "status"], in: object)
        {
            return state
        }
        return freshness?.status ?? self.state(lastSyncAt: lastSyncAt, fallback: fallback, staleAfterSeconds: staleAfterSeconds)
    }

    func statusCounts(in object: [String: Any], fallback: [CrawlCount]) -> [CrawlCount] {
        let declared = self.countArray(["counts"], in: object)
        return declared.isEmpty ? fallback : declared
    }

    func countArray(_ keys: [String], in object: [String: Any]) -> [CrawlCount] {
        for key in keys {
            guard let array = self.firstValue(key, in: object) as? [Any] else { continue }
            let counts = array.compactMap { item -> CrawlCount? in
                guard let item = item as? [String: Any],
                      let id = self.stringValue(["id"], in: item),
                      let value = self.intValue(["value", "count"], in: item)
                else { return nil }
                return CrawlCount(
                    id: id,
                    label: self.stringValue(["label"], in: item) ?? self.label(from: id),
                    value: value)
            }
            if !counts.isEmpty { return counts }
        }
        return []
    }

    func databaseResources(in object: [String: Any]) -> [CrawlDatabaseResource] {
        guard let array = self.firstValue("databases", in: object) as? [Any] else { return [] }
        return array.compactMap { item -> CrawlDatabaseResource? in
            guard let item = item as? [String: Any] else { return nil }
            let path = self.stringValue(["path"], in: item)
            guard let id = self.stringValue(["id"], in: item) ?? path else { return nil }
            let kindValue = self.stringValue(["kind"], in: item) ?? CrawlDatabaseKind.sqlite.rawValue
            return CrawlDatabaseResource(
                id: id,
                label: self.stringValue(["label"], in: item) ?? URL(fileURLWithPath: id).lastPathComponent,
                kind: CrawlDatabaseKind(rawValue: kindValue) ?? .remote,
                role: self.stringValue(["role"], in: item),
                path: path,
                endpoint: self.stringValue(["endpoint"], in: item),
                archive: self.stringValue(["archive"], in: item),
                isPrimary: self.boolValue(["is_primary", "primary"], in: item) ?? false,
                bytes: self.intValue(["bytes", "size_bytes"], in: item),
                modifiedAt: self.dateValue(["modified_at", "updated_at"], in: item),
                counts: self.countArray(["counts"], in: item))
        }
    }

    func databaseModifiedAt(_ databases: [CrawlDatabaseResource]) -> Date? {
        databases.first(where: { $0.isPrimary })?.modifiedAt
            ?? databases.compactMap(\.modifiedAt).max()
    }

    func shareStatus(in object: [String: Any]) -> CrawlShareStatus? {
        guard let share = self.firstObject(["share", "sharing", "published"], in: object) else { return nil }
        return CrawlShareStatus(
            enabled: (share["enabled"] as? Bool) ?? (share["repo_path"] != nil),
            repoPath: share["repo_path"] as? String,
            remote: share["remote"] as? String,
            branch: share["branch"] as? String,
            needsUpdate: share["needs_update"] as? Bool)
    }

    func remoteStatus(in object: [String: Any]) -> CrawlRemoteStatus? {
        let remote = self.firstObject(["remote"], in: object) ?? object
        let endpoint = self.stringValue(["endpoint"], in: remote)
        let archive = self.stringValue(["archive"], in: remote)
        let mode = self.stringValue(["mode"], in: remote)
        guard endpoint != nil || archive != nil || mode != nil else { return nil }
        return CrawlRemoteStatus(
            enabled: self.boolValue(["enabled"], in: remote) ?? true,
            mode: mode,
            endpoint: endpoint,
            archive: archive,
            lastIngestAt: self.dateValue(["last_ingest_at"], in: remote),
            lastSyncAt: self.dateValue(["last_sync_at"], in: remote),
            needsUpdate: self.boolValue(["needs_update"], in: remote))
    }

    func sqliteObjectStatus(in object: [String: Any]) -> CrawlSQLiteObjectStatus? {
        guard let sqliteObject = self.firstObject(["sqlite_object"], in: object) else { return nil }
        return CrawlSQLiteObjectStatus(
            key: self.stringValue(["key"], in: sqliteObject),
            contentType: self.stringValue(["content_type"], in: sqliteObject),
            bytes: self.intValue(["bytes", "size"], in: sqliteObject),
            uploadedAt: self.dateValue(["uploaded_at", "uploaded", "modified_at"], in: sqliteObject))
    }

    func sqliteBundleStatus(in object: [String: Any]) -> CrawlSQLiteBundleStatus? {
        guard let sqliteBundle = self.firstObject(["sqlite_bundle", "bundle"], in: object) else { return nil }
        let manifest = self.firstObject(["manifest"], in: sqliteBundle) ?? sqliteBundle
        let compression = self.firstObject(["compression"], in: manifest)
        let rawObject = self.firstObject(["object"], in: manifest)
        let compressedObject = self.firstObject(["compressed_object"], in: manifest)
        let parts = self.firstValue("parts", in: manifest) as? [Any]
        let compressedBytes = self.int(sqliteBundle["compressed_bytes"] as Any)
            ?? self.int(sqliteBundle["size"] as Any)
            ?? compressedObject.flatMap { self.intValue(["bytes", "size"], in: $0) }
        return CrawlSQLiteBundleStatus(
            key: self.stringValue(["key"], in: sqliteBundle),
            contentType: self.stringValue(["content_type"], in: sqliteBundle),
            format: self.stringValue(["format"], in: manifest),
            compression: compression.flatMap { self.stringValue(["algorithm"], in: $0) },
            rawBytes: self.int(sqliteBundle["raw_bytes"] as Any)
                ?? rawObject.flatMap { self.intValue(["bytes", "size"], in: $0) },
            compressedBytes: compressedBytes,
            partCount: self.intValue(["part_count"], in: sqliteBundle) ?? parts?.count,
            uploadedAt: self.dateValue(["uploaded_at", "uploaded", "modified_at"], in: sqliteBundle),
            generatedAt: self.dateValue(["generated_at"], in: manifest))
    }
}
