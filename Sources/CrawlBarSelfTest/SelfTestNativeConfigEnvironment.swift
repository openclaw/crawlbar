import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func testNativeConfigEnvironment() throws {
        try Self.testInheritedNativeSelection()
        try Self.testInheritedNativeRetry()
        try Self.testNativeSelectorPrecedence()
        try Self.testNativeSelectorPresence()
        try Self.testNativeLiteralSelectors()
        try Self.testNativeFrozenEnvironment()
    }

    private static func testInheritedNativeSelection() throws {
        for changed in [false, true] {
            let fixture = try NativeEnvironmentFixture(change: changed ? "changed" : "unchanged", defaultValue: changed ? "A" : "B")
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let runner = fixture.runner(selector: fixture.selectedURL.path)
            try fixture.expectInitial(runner: runner, denied: changed)
            try Self.expect(try Data(contentsOf: fixture.selectedURL) == NativeEnvironmentFixture.native(changed ? "B" : "A"), "only the inherited selected file changes")
            try fixture.expectUnchanged()
        }
    }

    private static func testInheritedNativeRetry() throws {
        for changed in [false, true] {
            let fixture = try NativeEnvironmentFixture(change: "retry")
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let runner = fixture.runner(selector: fixture.selectedURL.path)
            let coordinator = CrawlActionCoordinator()
            let now = Date()
            let first = try fixture.run(coordinator, runner: runner, now: now)
            try Self.expect(first.results.map(\.action) == ["pull", "share"] && first.results.map(\.exitCode) == [0, 7] && first.failure != nil, "real publication fails once after successful sync")
            let successfulSync = coordinator.lastSuccessfulSync(fixture.app.id)
            try Self.expect(successfulSync == first.results.first?.finishedAt, "retry records actual successful sync time")
            try Self.expect(try fixture.marker("sync") == "sync\n" && fixture.marker("publish") == "A\n", "first attempt invokes both real children")
            if changed { try NativeEnvironmentFixture.write(NativeEnvironmentFixture.native("B"), to: fixture.selectedURL) }
            let retry = try fixture.run(coordinator, runner: runner, now: now.addingTimeInterval(900), interval: 900)
            try Self.expect(retry.failure == nil && retry.results.map(\.action) == (changed ? [] : ["share"]), "due retry is share-only success or guard denial without child error")
            try Self.expect(try fixture.marker("sync") == "sync\n" && fixture.marker("publish") == (changed ? "A\n" : "A\nA\n"), "retry does not resync or invoke a denied publisher")
            try Self.expect(coordinator.lastSuccessfulSync(fixture.app.id) == successfulSync, "retry preserves successful sync time")
            try Self.expect(try Data(contentsOf: fixture.selectedURL) == NativeEnvironmentFixture.native(changed ? "B" : "A"), "retry does not rewrite selected config")
            try fixture.expectUnchanged()
        }
    }

    private static func testNativeSelectorPrecedence() throws {
        for variant in ["explicit", "option", "option-changed", "blank"] {
            var fixture = try NativeEnvironmentFixture(change: variant == "option-changed" ? "changed" : "unchanged")
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            var inherited = fixture.otherURL.path
            switch variant {
            case "explicit":
                fixture.installation.configPathOverride = "  \(fixture.selectedURL.path) \n"
            case "option", "option-changed":
                fixture.installation.configPathOverride = fixture.otherURL.path
                fixture.values["selector_first"] = fixture.otherURL.path
                fixture.values["selector_last"] = " \(fixture.selectedURL.path) "
                fixture.values["selector_blank"] = " \n"
            default:
                fixture.installation.configPathOverride = " \n"
                fixture.values["selector_first"] = " \n"
                inherited = fixture.selectedURL.path
            }
            let runner = fixture.runner(selector: inherited)
            try fixture.expectProbe(runner: runner, selector: fixture.selectedURL.path)
            try fixture.expectInitial(runner: runner, denied: variant == "option-changed")
            try Self.expect(try Data(contentsOf: fixture.selectedURL) == NativeEnvironmentFixture.native(variant == "option-changed" ? "B" : "A"), "precedence selects only the intended file")
            try fixture.expectUnchanged()
        }
    }

    private static func testNativeSelectorPresence() throws {
        for noConfigEnv in [false, true] {
            var fixture = try NativeEnvironmentFixture()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            if noConfigEnv {
                fixture.installation.manifest.paths.configEnv = nil
                fixture.installation.configPathOverride = fixture.defaultURL.path
            }
            let runner = fixture.runner(selector: nil)
            try fixture.expectProbe(runner: runner, selector: nil)
            try fixture.expectInitial(runner: runner, denied: false)
            try fixture.expectUnchanged()
        }
        for selector in ["", " \t "] {
            let fixture = try NativeEnvironmentFixture()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let runner = fixture.runner(selector: selector)
            // Probe presence/bytes without trying to open an empty filename.
            try fixture.expectProbe(runner: runner, selector: selector)
            try Self.expect(!FileManager.default.fileExists(atPath: selector), "blank selector has no literal file before guard evaluation")
            let permit = fixture.registry.nativePublicationGuard(for: fixture.installation, configValues: fixture.values, runner: runner)
            try Self.expect(!permit(), "present empty or unreadable literal selector does not fall back to readable A")
            try Self.expect(!FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("publish.marker").path), "direct denial never launches a publisher")
            try fixture.expectUnchanged()
        }
    }

    private static func testNativeLiteralSelectors() throws {
        let fixture = try NativeEnvironmentFixture(defaultValue: "B")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let literal = fixture.directory.appendingPathComponent(" selected.toml ")
        try NativeEnvironmentFixture.write(NativeEnvironmentFixture.native("A"), to: literal)
        try NativeEnvironmentFixture.write(NativeEnvironmentFixture.native("B"), to: fixture.selectedURL)
        let runner = fixture.runner(selector: literal.path)
        try fixture.expectProbe(runner: runner, selector: literal.path)
        try fixture.expectInitial(runner: runner, denied: false)
        try Self.expect(try Data(contentsOf: literal) == NativeEnvironmentFixture.native("A") && Data(contentsOf: fixture.selectedURL) == NativeEnvironmentFixture.native("B"), "literal whitespace and trimmed counterexample stay distinct")
        try fixture.expectUnchanged()

        let fm = FileManager.default
        let original = fm.currentDirectoryPath
        defer {
            precondition(fm.changeCurrentDirectoryPath(original) && fm.currentDirectoryPath == original, "fixture must restore the original cwd")
        }
        for relative in ["selected.toml", "~/selected.toml"] {
            let relativeFixture = try NativeEnvironmentFixture(defaultValue: "B")
            defer {
                precondition(fm.changeCurrentDirectoryPath(original) && fm.currentDirectoryPath == original, "restore cwd before fixture cleanup")
                try? fm.removeItem(at: relativeFixture.directory)
            }
            let cwd = relativeFixture.directory.appendingPathComponent("cwd")
            try fm.createDirectory(at: cwd.appendingPathComponent("~"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cwd.path)
            let selected = cwd.appendingPathComponent(relative)
            try NativeEnvironmentFixture.write(NativeEnvironmentFixture.native("A"), to: selected)
            try Self.expect(fm.changeCurrentDirectoryPath(cwd.path), "relative fixture enters its owned cwd")
            try Self.expect(fm.currentDirectoryPath == cwd.resolvingSymlinksInPath().path && fm.currentDirectoryPath != relativeFixture.home.path, "test cwd is the fixture directory, not runner HOME")
            let relativeRunner = relativeFixture.runner(selector: relative)
            try relativeFixture.expectProbe(runner: relativeRunner, selector: relative)
            try relativeFixture.expectInitial(runner: relativeRunner, denied: false)
            try Self.expect(try Data(contentsOf: selected) == NativeEnvironmentFixture.native("A"), "relative selector preserves selected bytes")
            try relativeFixture.expectUnchanged()
            try Self.expect(fm.changeCurrentDirectoryPath(original) && fm.currentDirectoryPath == original, "relative case restores cwd before cleanup")
        }
    }

    private static func testNativeFrozenEnvironment() throws {
        var fixture = try NativeEnvironmentFixture(defaultValue: "B")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var environment = fixture.environment(selector: fixture.otherURL.path)
        environment["FIXTURE_VALUE"] = "before"
        let runner = CrawlCommandRunner(environment: environment)
        environment["NATIVE_CONFIG"] = fixture.defaultURL.path
        environment["FIXTURE_VALUE"] = "after"
        try fixture.expectProbe(runner: runner, selector: fixture.otherURL.path)
        var values = fixture.values
        values["selector_first"] = fixture.selectedURL.path
        fixture.values = values
        values["selector_first"] = fixture.otherURL.path
        try fixture.expectProbe(runner: runner, selector: fixture.selectedURL.path)
        try Self.expect(try fixture.marker("value") == "before" && environment["FIXTURE_VALUE"] == "after" && values != fixture.values, "runner and action inputs remain frozen after caller dictionary edits")
        try fixture.expectInitial(runner: runner, denied: false)
        try fixture.expectUnchanged()
        fixture.values = ["destination": "A"]
        fixture.installation.configPathOverride = "  ~/crawlbar-fixture-not-opened.toml \n"
        // Transport comparison only: never open the expanded non-fixture path.
        try fixture.expectProbe(runner: runner, selector: PathExpander.expandHome("~/crawlbar-fixture-not-opened.toml"))
    }
}

private struct NativeEnvironmentFixture {
    let directory: URL
    let home: URL
    let mainURL: URL
    let defaultURL: URL
    let selectedURL: URL
    let otherURL: URL
    let app: CrawlBarAppConfig
    let registry: CrawlAppRegistry
    let initialMain: Data
    let initialDefault: Data
    var installation: CrawlAppInstallation
    var values: [String: String] = ["destination": "A"]

    init(change: String = "unchanged", defaultValue: String = "A") throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("crawlbar-configenv-\(UUID())")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var initialized = false
        defer { if !initialized { try? fm.removeItem(at: directory) } }
        let home = directory.appendingPathComponent("home")
        let apps = directory.appendingPathComponent("apps")
        for path in [home, apps] {
            try fm.createDirectory(at: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let main = directory.appendingPathComponent("config.json")
        let defaultURL = directory.appendingPathComponent("default.toml")
        let selected = directory.appendingPathComponent("selected.toml")
        let other = directory.appendingPathComponent("other.toml")
        let script = directory.appendingPathComponent("child.sh")
        try Self.write(Data(Self.script.utf8), to: script)
        try Self.write(Self.native(defaultValue), to: defaultURL)
        try Self.write(Self.native("A"), to: selected)
        try Self.write(Self.native("B"), to: other)
        try Self.write(Self.native("B"), to: home.appendingPathComponent("next.toml"))
        var specification = CrawlBarSelfTest.nativeFixtureManifest(commands: [
            "pull": [script.path, "sync", change, defaultURL.path],
            "share": [script.path, "publish", change, defaultURL.path],
            "probe": [script.path, "probe"],
        ], binary: "/bin/sh")
        specification.paths = .init(defaultConfig: defaultURL.path, configEnv: "NATIVE_CONFIG")
        specification.configOptions = [
            .init(id: "destination", label: "Destination", configKey: "share.repo_path"),
            .init(id: "selector_first", label: "First selector", envVar: "NATIVE_CONFIG"),
            .init(id: "selector_last", label: "Last selector", envVar: "NATIVE_CONFIG"),
            .init(id: "selector_blank", label: "Blank selector", defaultValue: "not-injected", envVar: "NATIVE_CONFIG"),
        ]
        try Self.write(try CrawlCoding.makeJSONEncoder().encode(specification), to: apps.appendingPathComponent("fixture.json"))
        let app = CrawlBarAppConfig(
            id: specification.id, binaryPath: "/bin/sh", preferredRefreshAction: "pull",
            shareEnabled: true, shareAfterRefresh: true, preferredShareAction: "share", configValues: ["destination": "A"])
        let config = CrawlBarConfig(manifestDirectories: [apps.path], apps: [app])
        let catalog = CrawlManifestCatalog(scanCache: CrawlManifestScanCache())
        guard let manifest = catalog.manifest(for: app.id, config: config) else {
            throw SelfTestError.failed("config environment external manifest was not discovered")
        }
        try CrawlBarSelfTest.expect(manifest == specification && catalog.diagnostics(config: config).isEmpty, "external manifest retains ordered selectors and config-only destination")
        let store = CrawlBarConfigStore(fileURL: main, cache: CrawlBarConfigCache())
        try store.save(config)
        let registry = CrawlAppRegistry(configStore: store, catalog: catalog, nativeConfigStore: CrawlNativeConfigStore(cache: CrawlNativeConfigCache()))
        self.directory = directory
        self.home = home
        self.mainURL = main
        self.defaultURL = defaultURL
        self.selectedURL = selected
        self.otherURL = other
        self.app = app
        self.registry = registry
        self.installation = CrawlAppInstallation(manifest: manifest, binaryPath: "/bin/sh", configValues: app.configValues)
        self.initialMain = try Data(contentsOf: main)
        self.initialDefault = try Data(contentsOf: defaultURL)
        initialized = true
    }

    func environment(selector: String?) -> [String: String] {
        var result = ["HOME": self.home.path, "TMPDIR": self.directory.path, "PATH": "/usr/bin:/bin"]
        result["NATIVE_CONFIG"] = selector
        return result
    }

    func runner(selector: String?) -> CrawlCommandRunner {
        CrawlCommandRunner(environment: self.environment(selector: selector))
    }

    func run(_ coordinator: CrawlActionCoordinator, runner: CrawlCommandRunner, now: Date = Date(), interval: TimeInterval? = nil) throws -> CrawlActionOutcome {
        let installation = self.installation
        let values = self.values
        let permit = self.registry.nativePublicationGuard(for: installation, configValues: values, runner: runner)
        var guardCalls = 0
        let outcome = try coordinator.run(
            installation: installation, config: self.app, configValues: values, action: "pull",
            now: now, scheduledInterval: interval, allowShare: {
                guardCalls += 1
                return permit()
            })
        { action in
            try runner.run(installation: installation, configValues: values, action: action, timeoutSeconds: 5)
        }
        try CrawlBarSelfTest.expect(guardCalls == 1, "automatic publication invokes the guard exactly once")
        return outcome
    }

    func expectInitial(runner: CrawlCommandRunner, denied: Bool) throws {
        let outcome = try self.run(CrawlActionCoordinator(), runner: runner)
        try CrawlBarSelfTest.expect(outcome.failure == nil && outcome.results.map(\.action) == (denied ? ["pull"] : ["pull", "share"]), "selected-file outcome is success or guard denial, not a child error")
        try CrawlBarSelfTest.expect(try self.marker("sync") == "sync\n" && self.marker("publish") == (denied ? "" : "A\n"), "real children obey native selection")
        if denied {
            try CrawlBarSelfTest.expect(!FileManager.default.fileExists(atPath: self.home.appendingPathComponent("publish.marker").path), "denied publisher never creates a marker")
        }
    }

    func expectProbe(runner: CrawlCommandRunner, selector: String?) throws {
        let result = try runner.run(installation: self.installation, configValues: self.values, action: "probe", timeoutSeconds: 5)
        try CrawlBarSelfTest.expect(result.succeeded, "presence-only environment probe succeeds")
        let expected = selector.map { "present\n" + $0 } ?? "absent\n"
        try CrawlBarSelfTest.expect(try self.marker("probe") == expected, "child sees exact selector presence and bytes")
    }

    func marker(_ name: String) throws -> String {
        let path = self.home.appendingPathComponent("\(name).marker")
        guard FileManager.default.fileExists(atPath: path.path) else { return "" }
        return try String(contentsOf: path, encoding: .utf8)
    }

    func expectUnchanged() throws {
        try CrawlBarSelfTest.expect(try Data(contentsOf: self.mainURL) == self.initialMain && Data(contentsOf: self.defaultURL) == self.initialDefault && Data(contentsOf: self.otherURL) == Self.native("B"), "main/default/unselected bytes remain unchanged")
    }

    static func native(_ destination: String) -> Data {
        Data("[share]\nrepo_path = \"\(destination)\"\n".utf8)
    }

    static func write(_ data: Data, to path: URL) throws {
        guard FileManager.default.createFile(atPath: path.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw SelfTestError.failed("could not create private config environment fixture")
        }
    }

    private static let script = #"""
    set -eu
    umask 077
    if [ "$1" = probe ]; then
      if [ "${NATIVE_CONFIG+x}" = x ]; then
        printf 'present\n%s' "$NATIVE_CONFIG" > "$HOME/probe.marker"
      else
        printf 'absent\n' > "$HOME/probe.marker"
      fi
      printf '%s' "${FIXTURE_VALUE-}" > "$HOME/value.marker"
      exit 0
    fi
    selected=${NATIVE_CONFIG-"$3"}
    case "$1" in
      sync)
        printf 'sync\n' >> "$HOME/sync.marker"
        if [ "$2" = changed ]; then /bin/cp "$HOME/next.toml" "$selected"; fi
        ;;
      publish)
        destination=$(/usr/bin/sed -n 's/^repo_path = "\(.*\)"$/\1/p' "$selected")
        printf '%s\n' "$destination" >> "$HOME/publish.marker"
        if [ "$2" = retry ] && [ ! -f "$HOME/failed.marker" ]; then
          printf 'failed\n' > "$HOME/failed.marker"
          exit 7
        fi
        ;;
      *) exit 64 ;;
    esac
    """#
}
