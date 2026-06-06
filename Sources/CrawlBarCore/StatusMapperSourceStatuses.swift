import Foundation

extension CrawlStatusMapper {
    func gitcrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let counts = [
            self.count("threads", "Threads", ["thread_count", "threads"]),
            self.count("open_threads", "Open Threads", ["open_thread_count", "open_threads"]),
            self.count("clusters", "Clusters", ["cluster_count", "clusters"]),
            self.count("repositories", "Repositories", ["repo_count", "repository_count", "repositories"]),
        ].compactMap { self.value($0, in: object) }

        let remote = self.remoteStatus(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "updated_at", "generated_at"], in: object)
            ?? remote?.lastSyncAt
            ?? remote?.lastIngestAt
        return CrawlAppStatus(
            appID: result.appID,
            state: self.state(lastSyncAt: lastSyncAt, fallback: .current, staleAfterSeconds: staleAfterSeconds),
            summary: self.summary(from: counts, fallback: "Git crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            lastSyncAt: lastSyncAt,
            counts: counts,
            freshness: self.freshness(in: object, lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds),
            share: self.shareStatus(in: object),
            remote: remote,
            sqliteObject: self.sqliteObjectStatus(in: object),
            sqliteBundle: self.sqliteBundleStatus(in: object))
    }

    func slacrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let flatCounts = [
            self.count("workspaces", "Workspaces", ["workspace_count", "workspaces"]),
            self.count("channels", "Channels", ["channel_count", "channels"]),
            self.count("users", "Users", ["user_count", "users"]),
            self.count("messages", "Messages", ["message_count", "messages"]),
        ].compactMap { self.value($0, in: object) }

        let counts = self.statusCounts(in: object, fallback: flatCounts)
        let databases = self.databaseResources(in: object)
        let remote = self.remoteStatus(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "latest_message_at", "updated_at"], in: object)
            ?? remote?.lastSyncAt
            ?? remote?.lastIngestAt
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
            share: self.shareStatus(in: object),
            remote: remote,
            sqliteObject: self.sqliteObjectStatus(in: object),
            sqliteBundle: self.sqliteBundleStatus(in: object))
    }

    func discrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
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
        let remote = self.remoteStatus(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "latest_message_at", "updated_at"], in: object)
            ?? remote?.lastSyncAt
            ?? remote?.lastIngestAt
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
            share: self.shareStatus(in: object),
            remote: remote,
            sqliteObject: self.sqliteObjectStatus(in: object),
            sqliteBundle: self.sqliteBundleStatus(in: object))
    }

    func telecrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
        let counts = [
            self.count("messages", "Messages", ["message_count", "messages"]),
            self.count("chats", "Chats", ["chat_count", "chats"]),
            self.count("folders", "Folders", ["folder_count", "folders"]),
            self.count("topics", "Topics", ["topic_count", "topics"]),
            self.count("unread_chats", "Unread Chats", ["unread_chat_count", "unread_chats"]),
            self.count("unread_messages", "Unread Messages", ["unread_message_count", "unread_messages"]),
            self.count("media_messages", "Media Messages", ["media_message_count", "media_messages"]),
        ].compactMap { self.value($0, in: object) }

        let lastSyncAt = self.dateValue(["last_sync_at", "last_import_at", "updated_at"], in: object)
        let freshness = self.freshness(in: object, lastSyncAt: lastSyncAt, staleAfterSeconds: staleAfterSeconds)
        return CrawlAppStatus(
            appID: result.appID,
            state: self.statusState(in: object, lastSyncAt: lastSyncAt, freshness: freshness, fallback: .current, staleAfterSeconds: staleAfterSeconds),
            summary: self.stringValue(["summary", "message"], in: object) ?? self.summary(from: counts, fallback: "Telegram crawl status is current"),
            configPath: self.stringValue(["config_path", "config"], in: object),
            databasePath: self.stringValue(["db_path", "database_path", "database"], in: object),
            databaseBytes: self.intValue(["db_bytes", "database_bytes"], in: object),
            lastSyncAt: lastSyncAt,
            lastImportAt: self.dateValue(["last_import_at"], in: object),
            counts: counts,
            freshness: freshness,
            share: self.shareStatus(in: object))
    }

    func notcrawlStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds: Int?) -> CrawlAppStatus {
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

        let remote = self.remoteStatus(in: object)
        let lastSyncAt = self.dateValue(["last_sync_at", "last_import_at", "updated_at"], in: object)
            ?? remote?.lastSyncAt
            ?? remote?.lastIngestAt
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
            share: self.shareStatus(in: object),
            remote: remote,
            sqliteObject: self.sqliteObjectStatus(in: object),
            sqliteBundle: self.sqliteBundleStatus(in: object))
    }
}
