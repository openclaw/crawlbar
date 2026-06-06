import Foundation

extension CrawlStatusMapper {
    func wacliStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let data = self.firstObject(["data"], in: object) ?? object
        let isAuthenticated = self.boolValue(["authenticated"], in: data) ?? true
        let storeError = self.stringValue(["store_error"], in: data)?.nilIfBlank
        if let storeError, (isAuthenticated || !Self.isWacliFirstRunStoreError(storeError)) {
            return CrawlAppStatus(
                appID: result.appID,
                state: .error,
                summary: storeError,
                errors: [storeError])
        }
        if !isAuthenticated {
            return CrawlAppStatus(
                appID: result.appID,
                state: .needsAuth,
                summary: "WhatsApp auth needs setup")
        }
        let store = self.firstObject(["store"], in: data) ?? data
        let counts = [
            self.count("messages", "Messages", ["messages", "message_count"]),
            self.count("chats", "Chats", ["chats", "chat_count"]),
            self.count("contacts", "Contacts", ["contacts", "contact_count"]),
            self.count("groups", "Groups", ["groups", "group_count"]),
        ].compactMap { self.value($0, in: store) }
        let lastSyncAt = self.dateValue(["last_sync_at"], in: store)
            ?? self.dateValue(["last_sync_at", "updated_at"], in: data)
        let freshness = self.freshness(in: object, lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds)
        let storeDir = self.stringValue(["store_dir"], in: data)
        let state: CrawlAppState
        if self.boolValue(["success"], in: object) == false {
            state = .error
        } else {
            state = self.statusValue(["state", "status"], in: data)
                ?? self.statusValue(["state", "status"], in: object)
                ?? self.statusState(in: object, lastSyncAt: lastSyncAt, freshness: freshness, fallback: .current, staleAfterSeconds: staleAfterSeconds)
        }
        return CrawlAppStatus(
            appID: result.appID,
            state: state,
            summary: self.summary(from: counts, fallback: state == .error ? self.stringValue(["error"], in: object) ?? "WhatsApp diagnostics failed" : "WhatsApp archive is current"),
            configPath: storeDir.map(Self.wacliConfigPath(storeDir:)),
            databasePath: storeDir.map(Self.wacliDatabasePath(storeDir:)),
            lastSyncAt: lastSyncAt,
            counts: counts,
            databases: storeDir.map { Self.wacliDatabaseResources(storeDir: $0, counts: counts) } ?? [],
            freshness: freshness,
            warnings: self.wacliWarnings(in: data),
            errors: self.wacliErrors(in: object))
    }

    func isWacliManifest(_ manifest: CrawlAppManifest) -> Bool {
        manifest.id == BuiltInCrawlApps.wacliID
            || manifest.id.rawValue.hasPrefix("wacli-")
            || manifest.binary.name == "wacli"
    }

    func wacliWarnings(in object: [String: Any]) -> [String] {
        var warnings: [String] = []
        if self.boolValue(["lock_held"], in: object) == true,
           let state = self.stringValue(["connection_state"], in: object)
        {
            warnings.append("Store is locked by \(state)")
        }
        if self.boolValue(["fts_enabled"], in: object) == false {
            warnings.append("Full-text search is not enabled")
        }
        return warnings
    }

    func wacliErrors(in object: [String: Any]) -> [String] {
        guard self.boolValue(["success"], in: object) == false else { return [] }
        if let error = self.stringValue(["error"], in: object) {
            return [error]
        }
        return ["wacli doctor reported failure"]
    }

    static func wacliConfigPath(storeDir: String) -> String {
        let storeURL = URL(fileURLWithPath: storeDir)
        if storeURL.deletingLastPathComponent().lastPathComponent == "accounts" {
            return storeURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("config.yaml")
                .path
        }
        return storeURL.appendingPathComponent("config.yaml").path
    }

    static func wacliDatabasePath(storeDir: String) -> String {
        URL(fileURLWithPath: storeDir).appendingPathComponent("wacli.db").path
    }

    static func wacliDatabaseResources(storeDir: String, counts: [CrawlCount]) -> [CrawlDatabaseResource] {
        let databasePath = Self.wacliDatabasePath(storeDir: storeDir)
        var resources = [
            CrawlDatabaseResource(
                id: databasePath,
                label: "WhatsApp SQLite database",
                kind: .sqlite,
                path: databasePath,
                isPrimary: true,
                counts: counts),
        ]
        if databasePath != storeDir {
            resources.append(CrawlDatabaseResource(
                id: storeDir,
                label: "WhatsApp store",
                kind: .logical,
                path: storeDir,
                counts: counts))
        }
        return resources
    }

    static func isWacliFirstRunStoreError(_ error: String) -> Bool {
        let lowercased = error.lowercased()
        return lowercased.contains("no such file")
            || lowercased.contains("not found")
            || lowercased.contains("missing")
            || lowercased.contains("uninitialized")
    }
}
