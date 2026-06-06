import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testGogStatusServiceVerifiesOAuthOrServiceAccount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crawlbar-gog-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let scriptURL = directory.appendingPathComponent("gog")
        try Data("""
        #!/bin/sh
        if [ "$2" = "list" ]; then
          printf '%s' '{"accounts":[{"email":"user@example.com","auth":"oauth","valid":true}]}'
        else
          printf '%s' '{"status":"ok","checks":[{"name":"tokens","status":"ok","detail":"1 readable OAuth token"}]}'
        fi
        """.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = CrawlAppManifest(
            id: BuiltInCrawlApps.gogcliID,
            displayName: "Google",
            description: "A Google crawler",
            binary: .init(name: scriptURL.path),
            branding: .init(symbolName: "g.circle", accentColor: "#4285F4"),
            paths: .init(),
            commands: [
                "status": ["auth", "list", "--check", "--json", "--no-input"],
                "doctor": ["auth", "doctor", "--check", "--json", "--no-input"],
            ],
            capabilities: [.status, .doctor])
        let installation = CrawlAppInstallation(manifest: manifest, binaryPath: scriptURL.path)
        let status = CrawlStatusService().status(for: installation, timeoutSeconds: 5)
        try Self.expect(status.state == .current, "gog status service verifies OAuth with doctor")

        let serviceScriptURL = directory.appendingPathComponent("gog-service")
        try Data("""
        #!/bin/sh
        if [ "$2" = "list" ]; then
          printf '%s' '{"accounts":[{"email":"admin@example.com","auth":"service_account","valid":true,"error":"service account (not checked)"}]}'
        else
          printf '%s' '{"status":"warn","checks":[{"name":"tokens","status":"warn","detail":"no OAuth tokens"}]}'
        fi
        """.utf8).write(to: serviceScriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: serviceScriptURL.path)

        let serviceManifest = CrawlAppManifest(
            id: BuiltInCrawlApps.gogcliID,
            displayName: "Google",
            description: "A Google crawler",
            binary: .init(name: serviceScriptURL.path),
            branding: .init(symbolName: "g.circle", accentColor: "#4285F4"),
            paths: .init(),
            commands: manifest.commands,
            capabilities: [.status, .doctor])
        let serviceInstallation = CrawlAppInstallation(manifest: serviceManifest, binaryPath: serviceScriptURL.path)
        let serviceStatus = CrawlStatusService().status(for: serviceInstallation, timeoutSeconds: 5)
        try Self.expect(serviceStatus.state == .current, "gog status service accepts service-account-only auth")
    }

    static func testActionFailuresPreserveStatusMetadata() throws {
        let lastSyncAt = Date(timeIntervalSince1970: 1_775_000_000)
        let metadata = CrawlAppStatus(
            appID: BuiltInCrawlApps.discrawlID,
            state: .current,
            summary: "5052 messages",
            configPath: "/tmp/discrawl.toml",
            databasePath: "/tmp/discrawl.db",
            databaseBytes: 36_397_056,
            lastSyncAt: lastSyncAt,
            counts: [CrawlCount(id: "messages", label: "Messages", value: 5052)],
            databases: [
                CrawlDatabaseResource(
                    id: "primary",
                    label: "Discord archive",
                    kind: .sqlite,
                    path: "/tmp/discrawl.db",
                    isPrimary: true,
                    bytes: 36_397_056),
            ],
            freshness: CrawlFreshness(status: .current, ageSeconds: 12, staleAfterSeconds: 86_400),
            share: CrawlShareStatus(enabled: true, repoPath: "/tmp/share", remote: "origin", branch: "main"),
            warnings: ["old warning"])
        let failure = CrawlAppStatus(
            appID: BuiltInCrawlApps.discrawlID,
            state: .error,
            summary: "refresh: network timed out",
            errors: ["network timed out"])

        let merged = metadata.mergingActionFailure(failure)
        try Self.expect(merged.state == .error, "action failure state is visible")
        try Self.expect(merged.summary == "refresh: network timed out", "action failure summary is visible")
        try Self.expect(merged.databasePath == metadata.databasePath, "action failure preserves database path")
        try Self.expect(merged.databases == metadata.databases, "action failure preserves databases")
        try Self.expect(merged.counts == metadata.counts, "action failure preserves counts")
        try Self.expect(merged.lastSyncAt == lastSyncAt, "action failure preserves last sync")
        try Self.expect(merged.share == metadata.share, "action failure preserves share metadata")
        try Self.expect(merged.warnings == ["old warning"], "action failure preserves existing warnings")
        try Self.expect(merged.errors == ["network timed out"], "action failure keeps failure errors")

        let githubAuthMessage = """
        [github] request GET /repos/openclaw/openclaw
        github GET /repos/openclaw/openclaw failed with status 401: {
          "message": "Bad credentials"
        }
        """
        let githubAuthFailure = CrawlAppStatus.commandFailure(
            appID: BuiltInCrawlApps.gitcrawlID,
            action: "refresh",
            message: githubAuthMessage,
            fallback: "refresh failed")
        try Self.expect(githubAuthFailure.state == .needsAuth, "gitcrawl auth failure action is recoverable")
        try Self.expect(
            githubAuthFailure.summary == "refresh: GitHub credentials rejected",
            "gitcrawl auth failure action summary is useful")

        let githubMetadata = CrawlAppStatus(
            appID: BuiltInCrawlApps.gitcrawlID,
            state: .current,
            summary: "1 repo",
            databasePath: "/tmp/gitcrawl.db",
            counts: [CrawlCount(id: "repositories", label: "Repositories", value: 1)])
        let mergedGithub = githubMetadata.mergingActionFailure(githubAuthFailure)
        try Self.expect(mergedGithub.state == .needsAuth, "action failure merge preserves auth state")
        try Self.expect(mergedGithub.summary == "refresh: GitHub credentials rejected", "action failure merge preserves auth summary")
        try Self.expect(mergedGithub.databasePath == githubMetadata.databasePath, "action failure merge preserves github metadata")

        let emptyRefreshed = CrawlAppStatus(
            appID: BuiltInCrawlApps.discrawlID,
            state: .error,
            summary: "status failed")
        let richest = CrawlAppStatus.richestMetadataStatus(emptyRefreshed, fallback: metadata)
        try Self.expect(richest == metadata, "previous rich metadata wins over empty refreshed status")

        let recoverableGraincrawlStatus = CrawlAppStatus(
            appID: BuiltInCrawlApps.graincrawlID,
            state: .error,
            summary: "private-api reports expired token, desktop-cache reports unsupported cache version 8")
        try Self.expect(
            recoverableGraincrawlStatus.isRecoverableGraincrawlSourceFailure,
            "graincrawl source status failures can render as stale")
        let graincrawlActionFailure = recoverableGraincrawlStatus.mergingActionFailure(CrawlAppStatus(
            appID: BuiltInCrawlApps.graincrawlID,
            state: .error,
            summary: "refresh: Granola access token expired",
            errors: ["Granola access token expired"]))
        try Self.expect(
            !graincrawlActionFailure.isRecoverableGraincrawlSourceFailure,
            "graincrawl action failures stay visible as errors")
    }
}
