import Foundation

public extension BuiltInCrawlApps {
    static let birdclaw = CrawlAppManifest(
        id: Self.birdclawID,
        displayName: "X",
        description: "X/Twitter connector through bird, with Birdclaw workspace support",
        binary: .init(name: "bird"),
        execution: .init(
            kind: .local,
            kindConfigID: "execution_mode",
            targetConfigID: "remote_target",
            runAsConfigID: "remote_run_as",
            remoteBinary: "bird"),
        branding: .init(symbolName: "xmark", accentColor: "#111111"),
        paths: .init(
            defaultConfig: "~/.birdclaw/config.json",
            defaultDatabase: "~/.birdclaw/birdclaw.sqlite",
            defaultCache: "~/.birdclaw/media"),
        commands: [
            "status": ["check", "--plain"],
            "doctor": ["check", "--plain"],
            "search": ["search", "-n", "10", "--json"],
        ],
        capabilities: [.status, .doctor, .search],
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false, localOnlyScopes: ["X archive", "DMs", "browser cookies"]),
        configOptions: [
            .init(id: "access_path", label: "Access path", kind: .choice, help: "Use bird first, or use Birdclaw when that host is authenticated through xurl.", defaultValue: "bird", choices: ["bird", "birdclaw"]),
            .init(id: "execution_mode", label: "Run location", kind: .choice, help: "Run bird on this Mac or over SSH on another machine.", defaultValue: "local", choices: ["local", "remote"]),
            .init(id: "remote_target", label: "SSH target", help: "SSH target that can run bird.", placeholder: "user@example-host"),
            .init(id: "remote_run_as", label: "Run as user", help: "Optional remote Unix user for sudo -u, when bird is installed under a service account.", placeholder: "crawl"),
        ],
        configSections: [
            .init(id: "execution", title: "Execution", optionIDs: ["access_path", "execution_mode"]),
            .init(id: "remote", title: "Remote Host", optionIDs: ["remote_target", "remote_run_as"]),
        ],
        install: .init(method: .homebrew, package: "steipete/tap/bird"))
}
