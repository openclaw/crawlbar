import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testStatusMapperNormalizesWacliDoctorOutput() throws {
        let result = CrawlCommandResult(
            appID: CrawlAppID(rawValue: "wacli-test"),
            action: "status",
            exitCode: 0,
            stdout: """
            {"success":true,"data":{"state":"current","store_dir":"/tmp/wacli-store","lock_held":true,"connection_state":"locked_by_other_process","authenticated":true,"fts_enabled":false,"store":{"messages":6991,"chats":677,"contacts":514,"groups":250,"last_sync_at":"2026-05-09T05:45:44Z"}},"error":null}
            """,
            stderr: "",
            startedAt: Date(timeIntervalSince1970: 1_775_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_001))
        let manifest = CrawlAppManifest(
            id: result.appID,
            displayName: "WhatsApp Test",
            description: "Remote WhatsApp archive",
            binary: .init(name: "ssh"),
            branding: .init(symbolName: "message.circle", accentColor: "#25D366"),
            paths: .init(),
            commands: ["status": ["host", "wacli --account test --read-only doctor --json"]],
            capabilities: [.status])
        let status = CrawlStatusMapper().status(from: result, manifest: manifest, staleAfterSeconds: 900)

        try Self.expect(status.state == .current, "wacli doctor honors explicit current state over stale timestamps")
        try Self.expect(status.freshness?.status == .stale, "wacli doctor still exposes stale freshness metadata")
        try Self.expect(status.summary == "6991 messages, 677 chats", "wacli doctor maps store counts")
        try Self.expect(status.databasePath == "/tmp/wacli-store/wacli.db", "wacli doctor maps database path")
        try Self.expect(status.lastSyncAt != nil, "wacli doctor maps last sync")
        try Self.expect(status.warnings.contains("Store is locked by locked_by_other_process"), "wacli lock is a warning")
        try Self.expect(status.warnings.contains("Full-text search is not enabled"), "wacli FTS state is a warning")
    }

    static func testStatusMapperNormalizesGogAuthStatus() throws {
        let needsAuthResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gogcliID,
            action: "status",
            exitCode: 0,
            stdout: """
            {"account":{"credentials_exists":false,"service_account_configured":false,"email":""},"config":{"exists":false,"path":"/tmp/gog/config.json"},"keyring":{"backend":"auto","source":"default"}}
            """,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let needsAuth = CrawlStatusMapper().status(from: needsAuthResult, manifest: BuiltInCrawlApps.gogcli)
        try Self.expect(needsAuth.state == .needsAuth, "gog auth status without credentials maps to needs auth")
        try Self.expect(needsAuth.summary == "Google account needs auth", "gog auth status has a useful setup summary")
        try Self.expect(needsAuth.configPath == "/tmp/gog/config.json", "gog auth status maps config path")

        let readyResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gogcliID,
            action: "status",
            exitCode: 0,
            stdout: """
            {"account":{"credentials_exists":true,"service_account_configured":false,"email":"user@example.com"},"config":{"exists":true,"path":"/tmp/gog/config.json"}}
            """,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let ready = CrawlStatusMapper().status(from: readyResult, manifest: BuiltInCrawlApps.gogcli)
        try Self.expect(ready.state == .needsAuth, "gog raw credentials still require verified token auth")
        try Self.expect(ready.summary == "Google account needs auth", "gog raw credentials keep setup summary")

        let doctorResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.gogcliID,
            action: "status",
            exitCode: 0,
            stdout: """
            {"checks":[{"name":"config.path","status":"warn","detail":"/tmp/gog/config.json (missing)"},{"name":"keyring.open","status":"ok","detail":"opened"},{"name":"tokens","status":"ok","detail":"4 readable OAuth tokens of 4 stored token accounts"},{"name":"refresh.default.user@example.com","status":"ok","detail":"refresh token exchange succeeded"}],"status":"warn"}
            """,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let doctor = CrawlStatusMapper().status(from: doctorResult, manifest: BuiltInCrawlApps.gogcli)
        try Self.expect(doctor.state == .current, "gog doctor maps readable refreshable tokens to current")
        try Self.expect(doctor.summary == "4 Google OAuth accounts readable", "gog doctor summarizes readable tokens")
        try Self.expect(doctor.warnings.contains("config.path: /tmp/gog/config.json (missing)"), "gog doctor preserves non-auth warnings")
    }

    static func testStatusMapperNormalizesBirdclawAuthStatus() throws {
        let result = CrawlCommandResult(
            appID: BuiltInCrawlApps.birdclawID,
            action: "status",
            exitCode: 0,
            stdout: """
            {"installed":false,"availableTransport":"local","statusText":"xurl not installed. local mode active."}
            """,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let status = CrawlStatusMapper().status(from: result, manifest: BuiltInCrawlApps.birdclaw)
        try Self.expect(status.state == .current, "birdclaw auth status keeps local mode usable")
        try Self.expect(status.summary == "xurl not installed. local mode active.", "birdclaw auth status has a useful summary")
        try Self.expect(status.warnings.contains("Transport: local"), "birdclaw auth status exposes transport")
        try Self.expect(status.warnings.contains("xurl not installed. local mode active."), "birdclaw auth status preserves transport warning")

        let birdResult = CrawlCommandResult(
            appID: BuiltInCrawlApps.birdclawID,
            action: "status",
            exitCode: 0,
            stdout: """
            [info] Credential check
            [ok] auth_token: abc...
            [ok] ct0: def...
            source: Chrome default profile
            [warn] Warnings:
               - No Twitter cookies found in Safari.
            [ok] Ready to tweet!
            """,
            stderr: "",
            startedAt: Date(),
            finishedAt: Date())
        let birdStatus = CrawlStatusMapper().status(from: birdResult, manifest: BuiltInCrawlApps.birdclaw)
        try Self.expect(birdStatus.state == .current, "bird check text maps to current when cookies are usable")
        try Self.expect(birdStatus.summary == "X cookies available via bird (Chrome default profile)", "bird check text exposes cookie source")
        try Self.expect(birdStatus.warnings.contains("No Twitter cookies found in Safari."), "bird check warnings are preserved")
    }

    static func testStatusMapperTrustsCrawlerState() throws {
        let result = CrawlCommandResult(
            appID: BuiltInCrawlApps.discrawlID,
            action: "status",
            exitCode: 0,
            stdout: """
            {"schema_version":"crawlkit.control.v1","state":"current","summary":"ok","last_sync_at":"2026-05-09T05:45:44Z","counts":[{"id":"messages","label":"Messages","value":10}]}
            """,
            stderr: "",
            startedAt: Date(timeIntervalSince1970: 1_775_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_775_000_001))
        let status = CrawlStatusMapper().status(
            from: result,
            manifest: BuiltInCrawlApps.discrawl,
            staleAfterSeconds: 900)

        try Self.expect(status.state == .current, "explicit crawler state wins over stale timestamp heuristics")
        try Self.expect(status.freshness?.status == .stale, "stale timestamp can still be shown as metadata")
    }
}
