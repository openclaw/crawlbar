import Foundation

public extension BuiltInCrawlApps {
    static let gogcli = CrawlAppManifest(
        id: Self.gogcliID,
        displayName: "Google",
        description: "Google Workspace and account automation",
        binary: .init(name: "gog"),
        execution: .init(
            kind: .local,
            kindConfigID: "execution_mode",
            targetConfigID: "remote_target",
            runAsConfigID: "remote_run_as",
            remoteEnvFileConfigID: "remote_env_file",
            remoteBinary: "gog"),
        branding: .init(symbolName: "g.circle", accentColor: "#4285F4"),
        paths: .init(
            defaultConfig: "~/Library/Application Support/gogcli/config.json",
            defaultCache: "~/Library/Application Support/gogcli",
            defaultLogs: "~/Library/Logs/gogcli"),
        commands: [
            "status": ["auth", "list", "--check", "--json", "--no-input"],
            "doctor": ["auth", "doctor", "--check", "--json", "--no-input"],
            "search": ["--json", "--no-input", "search"],
        ],
        capabilities: [.status, .doctor, .search],
        statusRequiresSecrets: false,
        privacy: .init(exportsSecrets: false, localOnlyScopes: ["Google account config", "OAuth token metadata"]),
        configOptions: [
            .init(id: "execution_mode", label: "Run location", kind: .choice, help: "Run gog on this Mac or over SSH on another machine.", defaultValue: "local", choices: ["local", "remote"]),
            .init(id: "remote_target", label: "SSH target", help: "SSH target that can run gog.", placeholder: "user@example-host"),
            .init(id: "remote_run_as", label: "Run as user", help: "Optional remote Unix user for sudo -u, when gog is installed under a service account.", placeholder: "service-user"),
            .init(id: "remote_env_file", label: "Remote env file", help: "Optional env file to source before running gog on the remote host.", placeholder: "/run/service/env"),
        ],
        configSections: [
            .init(id: "execution", title: "Execution", optionIDs: ["execution_mode"]),
            .init(id: "remote", title: "Remote Host", optionIDs: ["remote_target", "remote_run_as", "remote_env_file"]),
        ],
        install: .init(method: .homebrew, package: "openclaw/tap/gogcli"))
        .withSuggestion(Self.alwaysSuggest("Google"))
}
