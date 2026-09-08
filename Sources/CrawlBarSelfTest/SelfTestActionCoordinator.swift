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
        try Self.testSettingsShareConfigSnapshot()
    }

    static func testSettingsShareConfigSnapshot() throws {
        for change in [
            "unchanged", "secret-only", "share-disabled", "after-refresh-disabled",
            "missing-app", "missing-main", "corrupt-main", "persisted-destination",
            "native-destination", "config-path", "share-action", "refresh-action", "other-setting",
        ] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crawlbar-share-config-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let mainURL = directory.appendingPathComponent("config.json")
            let nativeURL = directory.appendingPathComponent("native.toml")
            var manifest = Self.nativeFixtureManifest(commands: ["pull": [], "share": []])
            manifest.configOptions = [
                .init(id: "destination", label: "Destination", configKey: "share.destination"),
                .init(id: "fixture_secret", label: "Fixture secret", kind: .secret, configKey: "auth.fixture"),
            ]
            let app = CrawlBarAppConfig(
                id: manifest.id, configPath: nativeURL.path, preferredRefreshAction: "pull",
                shareEnabled: true, shareAfterRefresh: true, preferredShareAction: "share")
            let store = CrawlBarConfigStore(fileURL: mainURL, cache: CrawlBarConfigCache())
            let nativeStore = CrawlNativeConfigStore(cache: CrawlNativeConfigCache())
            let registry = CrawlAppRegistry(configStore: store, nativeConfigStore: nativeStore)
            // No external manifests or secret-store calls are needed for this fixture.
            var persisted = CrawlBarConfig(manifestDirectories: [directory.appendingPathComponent("apps").path], apps: [app])
            try store.save(persisted)
            var native = app
            native.configValues = ["destination": "original", "fixture_secret": UUID().uuidString]
            try nativeStore.write(appConfig: native, manifest: manifest)
            var baseline = registry.appConfigWithNativeValues(app, manifest: manifest, includeSecrets: false)
            try Self.expect(baseline.configValues == ["destination": "original"], "Settings baseline contains native nonsecret values")
            baseline.configValues["fixture_secret"] = UUID().uuidString
            let installation = CrawlAppInstallation(manifest: manifest)
            let coordinator = CrawlActionCoordinator()
            var calls: [String] = []
            let outcome = try coordinator.run(
                installation: installation, config: baseline, configValues: [:], action: "pull",
                allowShare: { registry.matchesPersistedAppConfig(baseline, manifest: manifest) })
            { action in
                calls.append(action)
                if action == "pull" {
                    switch change {
                    case "share-disabled": persisted.apps[0].shareEnabled = false
                    case "after-refresh-disabled": persisted.apps[0].shareAfterRefresh = false
                    case "missing-app": persisted.apps.removeAll()
                    case "persisted-destination": persisted.apps[0].configValues["destination"] = "changed"
                    case "config-path": persisted.apps[0].configPath = directory.appendingPathComponent("other.toml").path
                    case "share-action": persisted.apps[0].preferredShareAction = "other-share"
                    case "refresh-action": persisted.apps[0].preferredRefreshAction = "other-refresh"
                    case "other-setting": persisted.apps[0].showInMenuBar = false
                    case "native-destination", "secret-only":
                        if change == "secret-only" {
                            native.configValues["fixture_secret"] = UUID().uuidString
                        } else {
                            native.configValues["destination"] = "changed"
                        }
                        try nativeStore.write(appConfig: native, manifest: manifest)
                    default: break
                    }
                    switch change {
                    case "missing-main":
                        try FileManager.default.removeItem(at: mainURL)
                    case "corrupt-main":
                        try Data("not-json".utf8).write(to: mainURL)
                        // Deterministically invalidate the existing mtime-based cache.
                        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: mainURL.path)
                    default:
                        try store.save(persisted)
                    }
                }
                return Self.actionFixtureResult(manifest.id, action: action, exitCode: 0)
            }
            let shouldPublish = change == "unchanged" || change == "secret-only"
            try Self.expect(outcome.failure == nil && calls == (shouldPublish ? ["pull", "share"] : ["pull"]), "Settings share gate: \(change)")
            var shareGateCalls = 0
            calls = []
            _ = try coordinator.run(
                installation: installation, config: baseline, configValues: [:], action: "share",
                allowShare: {
                    shareGateCalls += 1
                    return registry.matchesPersistedAppConfig(baseline, manifest: manifest)
                })
            { action in
                calls.append(action)
                return Self.actionFixtureResult(manifest.id, action: action, exitCode: 0)
            }
            try Self.expect(calls == ["share"] && shareGateCalls == 0, "standalone publication bypasses only the between-phase gate")
            if change == "missing-main" {
                try Self.expect(!FileManager.default.fileExists(atPath: mainURL.path), "share gate never recreates a missing main config")
            } else if change == "corrupt-main" {
                let data = try Data(contentsOf: mainURL)
                try Self.expect(data == Data("not-json".utf8), "share gate never repairs a corrupt main config")
            }
        }
    }

    static func actionFixtureResult(_ appID: CrawlAppID, action: String, exitCode: Int32, date: Date = Date()) -> CrawlCommandResult {
        CrawlCommandResult(
            appID: appID, action: action, exitCode: exitCode,
            stdout: "", stderr: exitCode == 0 ? "" : "synthetic failure",
            startedAt: date, finishedAt: date)
    }
}
