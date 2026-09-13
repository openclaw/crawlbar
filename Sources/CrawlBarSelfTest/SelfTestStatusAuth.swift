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

    static func testStatusMapperGoogleAccountStates() throws {
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
    }

    static func testStatusMapperWhatsAppStoreStates() throws {
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
    }

    static func testStatusMapperGitHubFailures() throws {
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
