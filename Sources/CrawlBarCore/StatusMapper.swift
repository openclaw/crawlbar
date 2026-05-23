import Foundation

public struct CrawlStatusMapper: Sendable {
    private static let defaultStaleAfterSeconds = 86_400

    public init() {}

    public func status(
        from result: CrawlCommandResult,
        manifest: CrawlAppManifest,
        staleAfterSeconds: Int? = nil)
        -> CrawlAppStatus
    {
        guard result.succeeded else {
            return CrawlAppStatus.commandFailure(
                appID: result.appID,
                message: result.stderr.nilIfBlank ?? result.stdout.nilIfBlank,
                fallback: "Command failed with exit \(result.exitCode)")
        }

        guard let object = self.parseObject(result.stdout) else {
            if manifest.id == BuiltInCrawlApps.birdclawID {
                return self.birdTextStatus(result)
            }
            return CrawlAppStatus(
                appID: result.appID,
                state: .unknown,
                summary: result.stdout.nilIfBlank ?? "Command succeeded without JSON output",
                warnings: ["Status command did not return parseable JSON"])
        }

        let status: CrawlAppStatus
        if self.isCrawlKitStatus(object) {
            status = self.genericStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
        } else {
            switch manifest.id {
            case BuiltInCrawlApps.gitcrawlID:
                status = self.gitcrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.slacrawlID:
                status = self.slacrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.discrawlID:
                status = self.discrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.notcrawlID:
                status = self.notcrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.gogcliID:
                status = self.gogStatus(object, result: result)
            default:
                if self.isWacliManifest(manifest) {
                    status = self.wacliStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
                } else {
                    status = self.genericStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
                }
            }
        }
        return CrawlDatabaseInventory.enrich(status, manifest: manifest)
    }

    private func gitcrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let counts = [
            self.count("threads", "Threads", ["thread_count", "threads"]),
            self.count("open_threads", "Open Threads", ["open_thread_count", "open_threads"]),
            self.count("clusters", "Clusters", ["cluster_count", "clusters"]),
            self.count("repositories", "Repositories", ["repo_count", "repository_count", "repositories"]),
        ].compactMap { self.value($0, in: object) }

        let lastSyncAt = self.dateValue(["last_sync_at", "updated_at", "generated_at"], in: object)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.state(lastSyncAt: lastSyncAt, fallback: .current, staleAfterSeconds: staleAfterSeconds),
            summary: self.summary(from: counts, fallback: "Git crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            freshness: self.freshness(in: object, lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds))
    }

    private func slacrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let flatCounts = [
            self.count("workspaces", "Workspaces", ["workspace_count", "workspaces"]),
            self.count("channels", "Channels", ["channel_count", "channels"]),
            self.count("users", "Users", ["user_count", "users"]),
            self.count("messages", "Messages", ["message_count", "messages"]),
        ].compactMap { self.value($0, in: object) }

        let counts = self.statusCounts(in: object, fallback: flatCounts)
        let databases = self.databaseResources(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "latest_message_at", "updated_at"], in: object)
            ?? self.databaseModifiedAt(databases)
        let freshness = self.freshness(in: object, lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.statusState(in: object, lastSyncAt: lastSyncAt, freshness: freshness, fallback: .current, staleAfterSeconds: staleAfterSeconds),
            summary: self.stringValue(["summary", "message"], in: object) ?? self.summary(from: counts, fallback: "Slack crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            databaseBytes: self.intValue(["db_bytes", "database_bytes"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            databases: databases,
            freshness: freshness,
            share: self.shareStatus(in: object))
    }

    private func gogStatus(_ object: [String: Any], result: CrawlCommandResult) -> CrawlAppStatus {
        let account = self.firstObject(["account"], in: object) ?? [:]
        let config = self.firstObject(["config"], in: object) ?? [:]
        let credentialsExist = self.boolValue(["credentials_exists"], in: account) ?? false
        let serviceAccountConfigured = self.boolValue(["service_account_configured"], in: account) ?? false
        let email = self.stringValue(["email", "account"], in: account)
        let configPath = self.stringValue(["path"], in: config)

        let state: CrawlAppState = (credentialsExist || serviceAccountConfigured) ? .current : .needsAuth
        var warnings: [String] = []
        if self.boolValue(["exists"], in: config) == false {
            warnings.append("gog config file not found")
        }
        let summary = email.map { "Google account \($0) is ready" }
            ?? (state == .current ? "Google account is ready" : "Google account needs auth")

        return CrawlAppStatus(
            appID: result.appID,
            state: state,
            summary: summary,
            configPath: configPath,
            warnings: warnings)
    }

    private func birdTextStatus(_ result: CrawlCommandResult) -> CrawlAppStatus {
        let output = [result.stdout, result.stderr].compactMap(\.nilIfBlank).joined(separator: "\n")
        let lowered = output.lowercased()
        let hasCredentialOK = lowered.contains("[ok] auth_token") || lowered.contains("ready to tweet")
        let state: CrawlAppState
        let summary: String
        if hasCredentialOK {
            state = .current
            summary = "X account is ready"
        } else if lowered.contains("no twitter cookies")
            || lowered.contains("no x cookies")
            || lowered.contains("auth_token")
            || lowered.contains("ct0")
        {
            state = .needsAuth
            summary = "X browser cookies not found"
        } else {
            state = .unknown
            summary = output.nilIfBlank ?? "bird check succeeded"
        }

        return CrawlAppStatus(
            appID: result.appID,
            state: state,
            summary: summary,
            warnings: self.birdWarnings(in: output))
    }

    private func discrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let flatCounts = [
            self.count("guilds", "Guilds", ["guild_count", "guilds"]),
            self.count("channels", "Channels", ["channel_count", "channels"]),
            self.count("threads", "Threads", ["thread_count", "threads"]),
            self.count("messages", "Messages", ["message_count", "messages"]),
            self.count("members", "Members", ["member_count", "members"]),
            self.count("embedding_backlog", "Embedding Backlog", ["embedding_backlog"]),
        ].compactMap { self.value($0, in: object) }

        let counts = self.statusCounts(in: object, fallback: flatCounts)
        let databases = self.databaseResources(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "latest_message_at", "updated_at"], in: object)
            ?? self.databaseModifiedAt(databases)
        let freshness = self.freshness(in: object, lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.statusState(in: object, lastSyncAt: lastSyncAt, freshness: freshness, fallback: .current, staleAfterSeconds: staleAfterSeconds),
            summary: self.stringValue(["summary", "message"], in: object) ?? self.summary(from: counts, fallback: "Discord crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            databaseBytes: self.intValue(["db_bytes", "database_bytes"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            databases: databases,
            freshness: freshness,
            share: self.shareStatus(in: object))
    }

    private func notcrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let counts = [
            self.count("spaces", "Spaces", ["space_count", "spaces"]),
            self.count("users", "Users", ["user_count", "users"]),
            self.count("teams", "Teams", ["team_count", "teams"]),
            self.count("pages", "Pages", ["page_count", "pages"]),
            self.count("blocks", "Blocks", ["block_count", "blocks"]),
            self.count("collections", "Collections", ["collection_count", "collections"]),
            self.count("comments", "Comments", ["comment_count", "comments"]),
            self.count("raw_records", "Raw Records", ["raw_record_count", "raw_records"]),
        ].compactMap { self.value($0, in: object) }

        let lastSyncAt = self.dateValue(["last_sync_at", "last_import_at", "updated_at"], in: object)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.state(lastSyncAt: lastSyncAt, fallback: .current, staleAfterSeconds: staleAfterSeconds),
            summary: self.summary(from: counts, fallback: "Notion crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            databaseBytes: self.intValue(["db_bytes", "database_bytes"], in: object),
            walBytes: self.intValue(["wal_bytes"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            freshness: self.freshness(in: object, lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds),
            share: self.shareStatus(in: object))
    }

    private func wacliStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let data = self.firstObject(["data"], in: object) ?? object
        let store = self.firstObject(["store"], in: data) ?? [:]
        let counts = [
            self.count("messages", "Messages", ["messages", "message_count"]),
            self.count("chats", "Chats", ["chats", "chat_count"]),
            self.count("contacts", "Contacts", ["contacts", "contact_count"]),
            self.count("groups", "Groups", ["groups", "group_count"]),
        ].compactMap { self.value($0, in: store) }
        let lastSyncAt = self.dateValue(["last_sync_at"], in: store)
            ?? self.dateValue(["last_sync_at", "updated_at"], in: data)
        let freshness = self.freshness(lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds)
        let authenticated = self.boolValue(["authenticated"], in: data)
        let state: CrawlAppState
        if authenticated == false {
            state = .needsAuth
        } else if self.boolValue(["success"], in: object) == false {
            state = .error
        } else {
            state = self.statusValue(["state", "status"], in: data)
                ?? self.statusValue(["state", "status"], in: object)
                ?? freshness?.status
                ?? .current
        }
        let storeDir = self.stringValue(["store_dir"], in: data)
        let warnings = self.wacliWarnings(in: data)
        return CrawlAppStatus(
            appID: result.appID,
            state: state,
            summary: self.summary(from: counts, fallback: authenticated == false ? "WhatsApp account needs auth" : "WhatsApp archive is current"),
            databasePath: storeDir,
            lastSyncAt: lastSyncAt,
            counts: counts,
            databases: storeDir.map {
                [CrawlDatabaseResource(
                    id: $0,
                    label: "WhatsApp store",
                    kind: .logical,
                    path: $0,
                    isPrimary: true,
                    counts: counts)]
            } ?? [],
            freshness: freshness,
            warnings: warnings,
            errors: self.wacliErrors(in: object))
    }

    private func genericStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let counts = self.statusCounts(in: object, fallback: self.counts(in: object))
        let databases = self.databaseResources(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "updated_at", "generated_at"], in: object)
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
            share: self.shareStatus(in: object))
    }

    private func isWacliManifest(_ manifest: CrawlAppManifest) -> Bool {
        manifest.id == BuiltInCrawlApps.wacliID
            || manifest.id.rawValue.hasPrefix("wacli-")
            || manifest.binary.name == "wacli"
    }

    private func wacliWarnings(in object: [String: Any]) -> [String] {
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

    private func birdWarnings(in output: String) -> [String] {
        var warnings: [String] = []
        var inWarningBlock = false
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("[warn]") {
                inWarningBlock = true
                let message = line.replacingOccurrences(of: "[warn]", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespacesAndNewlines))
                if let message = message.nilIfBlank, message.lowercased() != "warnings" {
                    warnings.append(message)
                }
                continue
            }
            guard inWarningBlock else { continue }
            if line.hasPrefix("[") { break }
            let message = line.trimmingCharacters(in: CharacterSet(charactersIn: "- ").union(.whitespacesAndNewlines))
            if let message = message.nilIfBlank {
                warnings.append(message)
            }
        }
        return warnings
    }

    private func wacliErrors(in object: [String: Any]) -> [String] {
        guard self.boolValue(["success"], in: object) == false else { return [] }
        if let error = self.stringValue(["error"], in: object) {
            return [error]
        }
        return ["wacli doctor reported failure"]
    }

    private func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func isCrawlKitStatus(_ object: [String: Any]) -> Bool {
        if let schema = self.stringValue(["schema_version"], in: object), schema.hasPrefix("crawlkit.control.") {
            return true
        }
        return self.firstValue("databases", in: object) != nil && self.firstValue("counts", in: object) != nil
    }

    private func count(_ id: String, _ label: String, _ keys: [String]) -> (String, String, [String]) {
        (id, label, keys)
    }

    private func value(_ spec: (String, String, [String]), in object: [String: Any]) -> CrawlCount? {
        guard let value = self.intValue(spec.2, in: object) else { return nil }
        return CrawlCount(id: spec.0, label: spec.1, value: value)
    }

    private func counts(in object: [String: Any]) -> [CrawlCount] {
        guard let counts = self.firstObject(["counts", "stats"], in: object) else { return [] }
        return counts.compactMap { key, value in
            guard let int = self.int(value) else { return nil }
            return CrawlCount(id: key, label: self.label(from: key), value: int)
        }
        .sorted { $0.id < $1.id }
    }

    private func state(lastSyncAt: Date?, fallback: CrawlAppState, staleAfterSeconds: Int?) -> CrawlAppState {
        guard let lastSyncAt else { return fallback }
        let threshold = staleAfterSeconds ?? Self.defaultStaleAfterSeconds
        return Date().timeIntervalSince(lastSyncAt) > TimeInterval(threshold) ? .stale : .current
    }

    private func freshness(lastSyncAt: Date?, staleAfterSeconds: Int?) -> CrawlFreshness? {
        guard let lastSyncAt else { return nil }
        let threshold = staleAfterSeconds ?? Self.defaultStaleAfterSeconds
        let ageSeconds = max(0, Int(Date().timeIntervalSince(lastSyncAt)))
        return CrawlFreshness(
            status: ageSeconds > threshold ? .stale : .current,
            ageSeconds: ageSeconds,
            staleAfterSeconds: threshold)
    }

    private func freshness(in object: [String: Any], lastSyncAt: Date?, staleAfterSeconds: Int?) -> CrawlFreshness? {
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

    private func summary(from counts: [CrawlCount], fallback: String) -> String {
        let visible = counts.prefix(2).map { "\($0.value) \($0.label.lowercased())" }
        return visible.isEmpty ? fallback : visible.joined(separator: ", ")
    }

    private func statusState(
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

    private func statusCounts(in object: [String: Any], fallback: [CrawlCount]) -> [CrawlCount] {
        let declared = self.countArray(["counts"], in: object)
        return declared.isEmpty ? fallback : declared
    }

    private func countArray(_ keys: [String], in object: [String: Any]) -> [CrawlCount] {
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

    private func databaseResources(in object: [String: Any]) -> [CrawlDatabaseResource] {
        guard let array = self.firstValue("databases", in: object) as? [Any] else { return [] }
        return array.compactMap { item -> CrawlDatabaseResource? in
            guard let item = item as? [String: Any] else { return nil }
            let path = self.stringValue(["path"], in: item)
            guard let id = self.stringValue(["id"], in: item) ?? path else { return nil }
            let kindValue = self.stringValue(["kind"], in: item) ?? CrawlDatabaseKind.sqlite.rawValue
            return CrawlDatabaseResource(
                id: id,
                label: self.stringValue(["label"], in: item) ?? URL(fileURLWithPath: id).lastPathComponent,
                kind: CrawlDatabaseKind(rawValue: kindValue) ?? .sqlite,
                role: self.stringValue(["role"], in: item),
                path: path,
                isPrimary: self.boolValue(["is_primary", "primary"], in: item) ?? false,
                bytes: self.intValue(["bytes", "size_bytes"], in: item),
                modifiedAt: self.dateValue(["modified_at", "updated_at"], in: item),
                counts: self.countArray(["counts"], in: item))
        }
    }

    private func databaseModifiedAt(_ databases: [CrawlDatabaseResource]) -> Date? {
        databases.first(where: { $0.isPrimary })?.modifiedAt
            ?? databases.compactMap(\.modifiedAt).max()
    }

    private func intValue(_ keys: [String], in object: [String: Any]) -> Int? {
        for key in keys {
            if let value = self.firstValue(key, in: object), let int = self.int(value) {
                return int
            }
        }
        return nil
    }

    private func boolValue(_ keys: [String], in object: [String: Any]) -> Bool? {
        for key in keys {
            guard let value = self.firstValue(key, in: object) else { continue }
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
            if let string = value as? String {
                switch string.lowercased() {
                case "true", "yes", "1":
                    return true
                case "false", "no", "0":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    private func stringValue(_ keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = self.firstValue(key, in: object) as? String, let string = value.nilIfBlank {
                return string
            }
        }
        return nil
    }

    private func statusValue(_ keys: [String], in object: [String: Any]) -> CrawlAppState? {
        guard let rawValue = self.stringValue(keys, in: object) else { return nil }
        if let state = CrawlAppState(rawValue: rawValue) {
            return state
        }
        switch rawValue.lowercased() {
        case "ok", "success", "healthy", "ready":
            return .current
        case "warning", "degraded":
            return .stale
        case "failed", "failure":
            return .error
        default:
            return nil
        }
    }

    private func dateValue(_ keys: [String], in object: [String: Any]) -> Date? {
        for key in keys {
            guard let value = self.firstValue(key, in: object) else { continue }
            if let date = self.date(value) {
                return date
            }
        }
        return nil
    }

    private func shareStatus(in object: [String: Any]) -> CrawlShareStatus? {
        guard let share = self.firstObject(["share", "sharing", "published"], in: object) else { return nil }
        return CrawlShareStatus(
            enabled: (share["enabled"] as? Bool) ?? (share["repo_path"] != nil),
            repoPath: share["repo_path"] as? String,
            remote: share["remote"] as? String,
            branch: share["branch"] as? String,
            needsUpdate: share["needs_update"] as? Bool)
    }

    private func firstObject(_ keys: [String], in object: [String: Any]) -> [String: Any]? {
        for key in keys {
            if let object = self.firstValue(key, in: object) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    private func firstValue(_ key: String, in object: [String: Any]) -> Any? {
        if let value = object[key] { return value }
        for value in object.values {
            if let nested = value as? [String: Any], let match = self.firstValue(key, in: nested) {
                return match
            }
        }
        return nil
    }

    private func int(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func date(_ value: Any) -> Date? {
        if let date = value as? Date { return date }
        if let number = value as? NSNumber {
            let seconds = number.doubleValue > 99_999_999_999 ? number.doubleValue / 1_000 : number.doubleValue
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = value as? String, let trimmed = string.nilIfBlank else { return nil }
        if let date = ISO8601DateFormatter.crawlBarDate(from: trimmed) {
            return date
        }
        if let seconds = Double(trimmed) {
            return Date(timeIntervalSince1970: seconds > 99_999_999_999 ? seconds / 1_000 : seconds)
        }
        return nil
    }

    private func label(from key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
