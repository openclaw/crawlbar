import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testActionAttemptCadenceAndShareRetry() throws {
        let coordinator = CrawlActionCoordinator()
        let installation = CrawlAppInstallation(manifest: Self.nativeFixtureManifest(commands: ["pull": ["sync", "--selected"], "share": ["publish", "--selected"]]))
        let config = CrawlBarAppConfig(id: installation.id, preferredRefreshAction: "pull", shareEnabled: true, shareAfterRefresh: true, preferredShareAction: "share")
        let now = Date(timeIntervalSince1970: 1000)
        var called: [String] = []
        let first = try coordinator.run(installation: installation, config: config, configValues: [:], action: "pull", now: now) { action in
            called.append(action)
            return Self.actionFixtureResult(installation.id, action: action, exitCode: action == "share" ? 1 : 0, date: now)
        }
        try Self.expect(called == ["pull", "share"] && first.failure != nil, "successful sync and failed share remain separate phases")
        try Self.expect(coordinator.lastSuccessfulSync(installation.id) == now, "successful sync survives a failed publication")
        try Self.expect(!coordinator.isDue(installation.id, interval: 900, now: now.addingTimeInterval(60)), "failed share cannot retry on every one-minute tick")
        called = []
        _ = try coordinator.run(installation: installation, config: config, configValues: [:], action: "pull", now: now.addingTimeInterval(900), scheduledInterval: 900) { action in
            called.append(action)
            return Self.actionFixtureResult(installation.id, action: action, exitCode: 0, date: now)
        }
        try Self.expect(called == ["share"], "retry publication without recrawling")
        do {
            _ = try coordinator.run(installation: installation, config: config, configValues: [:], action: "pull", now: now.addingTimeInterval(901), scheduledInterval: 900) { _ in
                throw SelfTestError.failed("not-due scheduled action executed")
            }
            throw SelfTestError.failed("stale due-list entry was accepted")
        } catch CrawlActionCoordinatorError.notDue {
        }
    }

    static func testActionExclusionAndConsent() throws {
        let coordinator = CrawlActionCoordinator()
        let installation = CrawlAppInstallation(manifest: Self.nativeFixtureManifest(commands: ["refresh": [], "publish": []]))
        let config = CrawlBarAppConfig(id: installation.id, shareEnabled: true, shareAfterRefresh: true)
        let other = CrawlAppInstallation(manifest: BuiltInCrawlApps.imsgcrawl)
        _ = try coordinator.run(installation: installation, config: config, configValues: [:], action: "refresh", allowShare: { false }) { action in
            try Self.expect(action == "refresh", "revoked consent prevents publication")
            do {
                _ = try coordinator.run(installation: installation, config: config, configValues: [:], action: "refresh") { _ in
                    throw SelfTestError.failed("overlapping same-crawler action executed")
                }
                throw SelfTestError.failed("same-crawler mutation was not excluded")
            } catch CrawlActionCoordinatorError.busy {
            }
            _ = try coordinator.run(installation: other, config: .init(id: other.id), configValues: [:], action: "refresh") { next in
                Self.actionFixtureResult(other.id, action: next, exitCode: 0)
            }
            return Self.actionFixtureResult(installation.id, action: action, exitCode: 0)
        }
        for enabled in [false, true] {
            for afterRefresh in [false, true] {
                var calls: [String] = []
                let selected = CrawlBarAppConfig(id: installation.id, shareEnabled: enabled, shareAfterRefresh: afterRefresh)
                _ = try coordinator.run(installation: installation, config: selected, configValues: [:], action: "refresh") { action in
                    calls.append(action)
                    return Self.actionFixtureResult(installation.id, action: action, exitCode: 0)
                }
                try Self.expect(calls == (enabled && afterRefresh ? ["refresh", "publish"] : ["refresh"]), "manual sync respects both share consent settings")
            }
        }
        var calls: [String] = []
        let failed = try coordinator.run(installation: installation, config: config, configValues: [:], action: "refresh") { action in
            calls.append(action)
            return Self.actionFixtureResult(installation.id, action: action, exitCode: 1)
        }
        try Self.expect(calls == ["refresh"] && failed.failure != nil, "failed sync cannot publish")
        let next = try coordinator.run(installation: installation, config: config, configValues: [:], action: "refresh") { action in
            Self.actionFixtureResult(installation.id, action: action, exitCode: 0)
        }
        try Self.expect(!coordinator.isCurrent(installation.id, generation: failed.generation) && coordinator.isCurrent(installation.id, generation: next.generation), "later actions invalidate stale completion updates")
    }

    static func testActionSelectedArgumentsAndChangedConfig() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crawlbar-actions-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = CrawlActionCoordinator()
        let manifest = Self.nativeFixtureManifest(commands: [
            "pull": ["%s", "sync:{config:selection}"],
            "share": ["%s", "publish:{config:selection}"],
        ])
        let installation = CrawlAppInstallation(manifest: manifest, binaryPath: "/usr/bin/printf")
        let config = CrawlBarAppConfig(
            id: installation.id, preferredRefreshAction: "pull",
            shareEnabled: true, shareAfterRefresh: true, preferredShareAction: "share")
        let runner = CrawlCommandRunner(environment: ["HOME": directory.path, "PATH": "/usr/bin:/bin"])
        let outcome = try coordinator.run(
            installation: installation, config: config, configValues: ["selection": "chosen"], action: "pull")
        { action in
            try runner.run(
                installation: installation, configValues: ["selection": "chosen"],
                action: action, timeoutSeconds: 5)
        }
        try Self.expect(outcome.results.map(\.stdout) == ["sync:chosen", "publish:chosen"], "selected action argv reaches the actual runner for both phases")
        _ = try coordinator.run(
            installation: installation, config: config, configValues: ["selection": "old"], action: "pull")
        { action in
            Self.actionFixtureResult(installation.id, action: action, exitCode: action == "share" ? 1 : 0)
        }
        var calls: [String] = []
        _ = try coordinator.run(
            installation: installation, config: config, configValues: ["selection": "new"], action: "pull")
        { action in
            calls.append(action)
            return Self.actionFixtureResult(installation.id, action: action, exitCode: 0)
        }
        try Self.expect(calls == ["pull", "share"], "changed configuration invalidates a share-only retry")
        _ = try coordinator.run(
            installation: installation, config: config, configValues: [:], action: "pull")
        { action in
            Self.actionFixtureResult(installation.id, action: action, exitCode: action == "share" ? 1 : 0)
        }
        calls = []
        _ = try coordinator.run(installation: installation, config: config, configValues: [:], action: "pull") { action in
            calls.append(action)
            return Self.actionFixtureResult(installation.id, action: action, exitCode: 0)
        }
        try Self.expect(calls == ["pull", "share"], "explicit manual sync never turns into a publish-only retry")
    }

    static func actionFixtureResult(_ appID: CrawlAppID, action: String, exitCode: Int32, date: Date = Date()) -> CrawlCommandResult {
        CrawlCommandResult(
            appID: appID, action: action, exitCode: exitCode,
            stdout: "", stderr: exitCode == 0 ? "" : "synthetic failure",
            startedAt: date, finishedAt: date)
    }
}
