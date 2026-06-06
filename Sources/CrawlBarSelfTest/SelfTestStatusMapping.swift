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

        let gogResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gogcliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"account":{"credentials_exists":true},"config":{"exists":true,"path":"/tmp/gog/config.json"}}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let gogStatus = CrawlStatusMapper().status(from: gogResult, manifest: BuiltInCrawlApps.gogcli)
        try Self.expect(gogStatus.state == .needsAuth, "gog raw status asks OAuth auth to be verified")
        try Self.expect(gogStatus.configPath == "/tmp/gog/config.json", "gog config path maps")

        let gogServiceAccountRawResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gogcliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"account":{"service_account_configured":true},"config":{"exists":false}}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let gogServiceAccountRawStatus = CrawlStatusMapper().status(from: gogServiceAccountRawResult, manifest: BuiltInCrawlApps.gogcli)
        try Self.expect(gogServiceAccountRawStatus.state == .current, "gog raw status maps service account auth")

        let gogServiceAccountResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gogcliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"status":"ok","checks":[{"name":"config.path","status":"ok","detail":"/tmp/gog/config.json"},{"name":"service_account","status":"ok"}]}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let gogServiceAccountStatus = CrawlStatusMapper().status(from: gogServiceAccountResult, manifest: BuiltInCrawlApps.gogcli)
        try Self.expect(gogServiceAccountStatus.state == .current, "gog doctor maps configured auth")
        try Self.expect(gogServiceAccountStatus.configPath == "/tmp/gog/config.json", "gog doctor config path maps")

        let gogDoctorFailureResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gogcliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"status":"error","checks":[{"name":"tokens","status":"error","detail":"no readable OAuth tokens"}]}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let gogDoctorFailureStatus = CrawlStatusMapper().status(from: gogDoctorFailureResult, manifest: BuiltInCrawlApps.gogcli)
        try Self.expect(gogDoctorFailureStatus.state == .needsAuth, "gog doctor token failures map to auth setup")
        try Self.expect(gogDoctorFailureStatus.summary == "no readable OAuth tokens", "gog doctor failure detail maps")

        let gogDoctorConfigResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gogcliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"status":"warn","checks":[{"name":"config.path","status":"warn","detail":"config missing"}]}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let gogDoctorConfigStatus = CrawlStatusMapper().status(from: gogDoctorConfigResult, manifest: BuiltInCrawlApps.gogcli)
        try Self.expect(gogDoctorConfigStatus.state == .needsConfig, "gog doctor config warnings map to config setup")

        let wacliResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.wacliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"success":true,"data":{"store_dir":"/tmp/wacli/accounts/me","authenticated":true,"store":{"messages":12,"chats":3,"last_sync_at":"2026-05-01T12:00:00Z"}}}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let wacliStatus = CrawlStatusMapper().status(from: wacliResult, manifest: BuiltInCrawlApps.wacli)
        try Self.expect(wacliStatus.counts.contains(CrawlCount(id: "messages", label: "Messages", value: 12)), "wacli message counts map")
        try Self.expect(wacliStatus.configPath == "/tmp/wacli/config.yaml", "wacli account config path maps")
        try Self.expect(wacliStatus.databasePath == "/tmp/wacli/accounts/me/wacli.db", "wacli database path maps")
        try Self.expect(wacliStatus.databases.contains { $0.kind == .sqlite && $0.path == "/tmp/wacli/accounts/me/wacli.db" }, "wacli database inventory keeps sqlite resource")
        try Self.expect(wacliStatus.databases.contains { $0.kind == .logical && $0.path == "/tmp/wacli/accounts/me" }, "wacli database inventory keeps logical store")

        let wacliStoreErrorResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.wacliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"success":true,"data":{"authenticated":true,"store_error":"database disk image is malformed"}}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let wacliStoreErrorStatus = CrawlStatusMapper().status(from: wacliStoreErrorResult, manifest: BuiltInCrawlApps.wacli)
        try Self.expect(wacliStoreErrorStatus.state == .error, "wacli store errors map to error status")
        try Self.expect(wacliStoreErrorStatus.errors.contains("database disk image is malformed"), "wacli store error is preserved")

        let wacliFirstRunResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.wacliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"success":true,"data":{"authenticated":false,"store_error":"open store: no such file"}}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let wacliFirstRunStatus = CrawlStatusMapper().status(from: wacliFirstRunResult, manifest: BuiltInCrawlApps.wacli)
        try Self.expect(wacliFirstRunStatus.state == .needsAuth, "wacli first-run store errors stay auth setup")
        try Self.expect(wacliFirstRunStatus.summary == "WhatsApp auth needs setup", "wacli first-run summary stays setup-oriented")

        let wacliCorruptUnauthedResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.wacliID,
            action: "status",
            exitCode: 0,
            stdout: #"{"success":true,"data":{"authenticated":false,"store_error":"database disk image is malformed"}}"#,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let wacliCorruptUnauthedStatus = CrawlStatusMapper().status(from: wacliCorruptUnauthedResult, manifest: BuiltInCrawlApps.wacli)
        try Self.expect(wacliCorruptUnauthedStatus.state == .error, "wacli corrupt unauthenticated stores stay errors")

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

        let githubAuthMessage = """
        [github] request GET /repos/openclaw/openclaw
        github GET /repos/openclaw/openclaw failed with status 401: {
          "message": "Bad credentials"
        }
        """
        let githubAuthResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gitcrawlID,
            action: "status",
            exitCode: 1,
            stdout: "",
            stderr: githubAuthMessage,
            startedAt: Date(),
            finishedAt: Date())
        let githubAuthStatus = CrawlStatusMapper().status(from: githubAuthResult, manifest: BuiltInCrawlApps.gitcrawl)
        try Self.expect(githubAuthStatus.state == .needsAuth, "gitcrawl 401 maps to auth state")
        try Self.expect(githubAuthStatus.summary == "GitHub credentials rejected", "gitcrawl 401 uses useful summary")
        try Self.expect(githubAuthStatus.errors == ["GitHub credentials rejected"], "gitcrawl 401 keeps request trace out of status errors")

        let githubServerMessage = """
        [github] request GET /repos/openclaw/openclaw
        github GET /repos/openclaw/openclaw failed with status 500
        """
        let githubServerStatus = CrawlAppStatus.commandFailure(
            appID: BuiltInCrawlApps.gitcrawlID,
            action: "refresh",
            message: githubServerMessage,
            fallback: "refresh failed")
        try Self.expect(
            githubServerStatus.summary == "refresh: github GET /repos/openclaw/openclaw failed with status 500",
            "gitcrawl request trace is skipped in failure summaries")
    }
}
