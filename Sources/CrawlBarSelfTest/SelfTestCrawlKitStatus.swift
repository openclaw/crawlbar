import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testStatusMapperCrawlKitArchives() throws {
        let crawlKitOutput = """
        {
          "schema_version": "crawlkit.control.v1",
          "app_id": "discrawl",
          "state": "current",
          "summary": "5052 messages across 293 channels",
          "database_path": "/tmp/discrawl.db",
          "database_bytes": 36397056,
          "counts": [
            {"id": "guilds", "label": "Guilds", "value": 56},
            {"id": "channels", "label": "Channels", "value": 293},
            {"id": "messages", "label": "Messages", "value": 5052}
          ],
          "databases": [
            {
              "id": "primary",
              "label": "Discord archive",
              "kind": "sqlite",
              "role": "archive",
              "path": "/tmp/discrawl.db",
              "is_primary": true,
              "bytes": 36397056,
              "modified_at": "2026-04-24T07:38:30Z",
              "counts": [
                {"id": "messages", "label": "Messages", "value": 5052}
              ]
            }
          ]
        }
        """
        let crawlKitResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.discrawlID,
            action: "status",
            exitCode: 0,
            stdout: crawlKitOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())

        let crawlKitStatus = CrawlStatusMapper().status(from: crawlKitResult, manifest: BuiltInCrawlApps.discrawl)
        try Self.expect(crawlKitStatus.summary == "5052 messages across 293 channels", "crawlkit status summary maps")
        try Self.expect(crawlKitStatus.state == .current, "crawlkit explicit state maps")
        try Self.expect(crawlKitStatus.databaseBytes == 36397056, "crawlkit database bytes map")
        try Self.expect(crawlKitStatus.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 5052)), "crawlkit count array maps")
        try Self.expect(crawlKitStatus.databases.first?.id == "primary", "crawlkit databases map")
        try Self.expect(crawlKitStatus.databases.first?.modifiedAt != nil, "crawlkit database modified date maps")
        try Self.expect(crawlKitStatus.databases.first?.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 5052)) == true, "crawlkit database counts map")

        let cloudOutput = """
        {
          "schema_version": "crawlkit.control.v1",
          "app_id": "discrawl",
          "state": "current",
          "summary": "1417329 messages in remote archive discrawl/openclaw",
          "config_path": "/tmp/discrawl.toml",
          "counts": [
            {"id": "channels", "label": "Channels", "value": 23956},
            {"id": "messages", "label": "Messages", "value": 1417329},
            {"id": "members", "label": "Members", "value": 173089}
          ],
          "remote": {
            "enabled": true,
            "mode": "cloud",
            "endpoint": "https://crawl.example.test",
            "archive": "discrawl/openclaw",
            "last_ingest_at": "2026-05-28T19:30:56.840Z"
          },
          "databases": [
            {
              "id": "remote",
              "label": "Discord cloud archive",
              "kind": "cloudflare-d1",
              "role": "archive",
              "endpoint": "https://crawl.example.test",
              "archive": "discrawl/openclaw",
              "is_primary": true,
              "counts": [
                {"id": "messages", "label": "Messages", "value": 1417329}
              ]
            }
          ],
          "sqlite_bundle": {
            "key": "v1/discrawl/discrawl%2Fopenclaw/sqlite/current.manifest.json",
            "content_type": "application/json",
            "uploaded_at": "2026-05-28T19:30:56.840Z",
            "manifest": {
              "format": "sqlite-gzip-chunked-v1",
              "generated_at": "2026-05-28T19:30:41Z",
              "compression": {"algorithm": "gzip"},
              "object": {"key": "v1/discrawl/discrawl%2Fopenclaw/sqlite/current.db", "size": 839589888, "sha256": "raw"},
              "compressed_object": {"key": "v1/discrawl/discrawl%2Fopenclaw/sqlite/current.db.gz", "size": 259315038, "sha256": "compressed"},
              "parts": [
                {"index": 0, "key": "part-0", "size": 67108864, "sha256": "a"},
                {"index": 1, "key": "part-1", "size": 67108864, "sha256": "b"},
                {"index": 2, "key": "part-2", "size": 67108864, "sha256": "c"},
                {"index": 3, "key": "part-3", "size": 57988446, "sha256": "d"}
              ]
            }
          }
        }
        """
        let cloudResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.discrawlID,
            action: "status",
            exitCode: 0,
            stdout: cloudOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let cloudStatus = CrawlStatusMapper().status(from: cloudResult, manifest: BuiltInCrawlApps.discrawl)
        try Self.expect(cloudStatus.remote?.archive == "discrawl/openclaw", "remote archive maps")
        try Self.expect(cloudStatus.lastSyncAt != nil, "remote ingest maps as sync freshness")
        try Self.expect(cloudStatus.databases.first?.kind == .cloudflareD1, "remote database kind maps")
        try Self.expect(cloudStatus.databases.first?.endpoint == "https://crawl.example.test", "remote database endpoint maps")
        try Self.expect(cloudStatus.sqliteBundle?.format == "sqlite-gzip-chunked-v1", "sqlite bundle format maps")
        try Self.expect(cloudStatus.sqliteBundle?.compression == "gzip", "sqlite bundle compression maps")
        try Self.expect(cloudStatus.sqliteBundle?.rawBytes == 839589888, "sqlite bundle raw size maps")
        try Self.expect(cloudStatus.sqliteBundle?.compressedBytes == 259315038, "sqlite bundle compressed size maps")
        try Self.expect(cloudStatus.sqliteBundle?.partCount == 4, "sqlite bundle part count maps")
    }

    static func testStatusMapperCrawlKitStates() throws {
        let okOutput = """
        {
          "schema_version": "crawlkit.control.v1",
          "app_id": "graincrawl",
          "state": "ok",
          "summary": "1 notes",
          "counts": [{"id": "notes", "label": "Notes", "value": 1}]
        }
        """
        let okResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "status",
            exitCode: 0,
            stdout: okOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let okStatus = CrawlStatusMapper().status(from: okResult, manifest: BuiltInCrawlApps.graincrawl)
        try Self.expect(okStatus.state == .current, "crawlkit ok state maps to current")

        let weicrawlOutput = """
        {
          "archive": { "message_count": 7 },
          "control": {
            "schema_version": "crawlkit.control.v1",
            "app_id": "weicrawl",
            "state": "ok",
            "summary": "local WeChat archive",
            "config_path": "/tmp/weicrawl.toml",
            "database_path": "/tmp/weicrawl.db",
            "counts": [
              {"id": "profiles", "label": "Profiles", "value": 1},
              {"id": "messages", "label": "Messages", "value": 7}
            ],
            "databases": [
              {
                "id": "archive",
                "label": "weicrawl archive",
                "kind": "sqlite",
                "role": "archive",
                "path": "/tmp/weicrawl.db",
                "is_primary": true,
                "bytes": 200704
              }
            ],
            "warnings": ["WeChat container was not found"]
          }
        }
        """
        let weicrawlResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.weicrawlID,
            action: "status",
            exitCode: 0,
            stdout: weicrawlOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let weicrawlStatus = CrawlStatusMapper().status(from: weicrawlResult, manifest: BuiltInCrawlApps.weicrawl)
        try Self.expect(weicrawlStatus.summary == "local WeChat archive", "weicrawl nested crawlkit summary maps")
        try Self.expect(weicrawlStatus.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 7)), "weicrawl nested crawlkit counts map")
        try Self.expect(weicrawlStatus.databasePath == "/tmp/weicrawl.db", "weicrawl nested crawlkit database maps")
        try Self.expect(weicrawlStatus.databases.first?.label == "weicrawl archive", "weicrawl nested crawlkit database resources map")
        try Self.expect(weicrawlStatus.warnings == ["WeChat container was not found"], "weicrawl nested crawlkit warnings map")

        let failedOutput = """
        {"schema_version":"crawlkit.control.v1","app_id":"graincrawl","state":"failed","summary":"broken"}
        """
        let failedResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.graincrawlID,
            action: "status",
            exitCode: 0,
            stdout: failedOutput,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let failedStatus = CrawlStatusMapper().status(from: failedResult, manifest: BuiltInCrawlApps.graincrawl)
        try Self.expect(failedStatus.state == .error, "crawlkit failed state maps to error")

        let imsgcrawlSourceErrorResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.imsgcrawlID,
            action: "status",
            exitCode: 0,
            stdout: """
            {
              "schema_version": "crawlkit.control.v1",
              "app_id": "imsgcrawl",
              "state": "source_error",
              "summary": "Messages source could not be read.",
              "warnings": ["archive has not been synced"],
              "errors": ["Messages database access was denied"]
            }
            """,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let imsgcrawlSourceErrorStatus = CrawlStatusMapper().status(
            from: imsgcrawlSourceErrorResult,
            manifest: BuiltInCrawlApps.imsgcrawl)
        try Self.expect(imsgcrawlSourceErrorStatus.state == .error, "crawlkit source errors map to error")
        try Self.expect(imsgcrawlSourceErrorStatus.warnings == ["archive has not been synced"], "crawlkit warnings are preserved")
        try Self.expect(imsgcrawlSourceErrorStatus.errors == ["Messages database access was denied"], "crawlkit errors are preserved")
    }
}
