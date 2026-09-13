import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testStatusMapperNormalizesCounts() throws {
        let output = """
        {"message_count":42,"channel_count":3,"last_sync_at":"2026-05-01T12:00:00Z","db_path":"/tmp/discrawl.db"}
        """
        let result = CrawlCommandResult(
            appID: BuiltInCrawlApps.discrawlID,
            action: "status",
            exitCode: 0,
            stdout: output,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())

        let status = CrawlStatusMapper().status(from: result, manifest: BuiltInCrawlApps.discrawl)
        try Self.expect(status.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 42)), "discrawl messages map")
        try Self.expect(status.lastSyncAt != nil, "whole-second last sync dates map")
        try Self.expect(status.databasePath == "/tmp/discrawl.db", "database path maps")
        try Self.expect(status.databases.first?.label == "Discord archive", "database inventory maps")
        try Self.expect(status.databases.first?.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 42)) == true, "database inventory carries counts")
    }

    static func testStatusMapperTelegramFreshness() throws {
        let telecrawlOutput = """
        {
          "db_path": "/tmp/telecrawl.db",
          "chats": 3,
          "messages": 42,
          "unread_chats": 1,
          "unread_messages": 5,
          "media_messages": 6,
          "folders": 2,
          "topics": 4,
          "last_import_at": "2026-05-01T12:00:00Z"
        }
        """
        let telecrawlResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.telecrawlID,
            action: "status",
            exitCode: 0,
            stdout: telecrawlOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let telecrawlStatus = CrawlStatusMapper().status(
            from: telecrawlResult,
            manifest: BuiltInCrawlApps.telecrawl,
            staleAfterSeconds: 60)
        try Self.expect(telecrawlStatus.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 42)), "telecrawl messages map")
        try Self.expect(telecrawlStatus.counts.contains(CrawlCount(id: "chats", label: "Chats", value: 3)), "telecrawl chats map")
        try Self.expect(telecrawlStatus.lastSyncAt == telecrawlStatus.lastImportAt, "telecrawl import time maps to sync freshness")
        try Self.expect(telecrawlStatus.state == .stale, "telecrawl import freshness drives stale state")
        try Self.expect(telecrawlStatus.databases.first?.label == "Telegram archive", "telecrawl database inventory maps")
    }
}
