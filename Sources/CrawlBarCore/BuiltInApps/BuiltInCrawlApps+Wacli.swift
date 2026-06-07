import Foundation

public extension BuiltInCrawlApps {
    static let wacli = CrawlAppManifest(
        id: Self.wacliID,
        displayName: "WhatsApp",
        description: "WhatsApp linked-device message archive",
        binary: .init(name: "wacli"),
        execution: .init(
            kind: .local,
            kindConfigID: "execution_mode",
            targetConfigID: "remote_target",
            runAsConfigID: "remote_run_as",
            remoteBinary: "wacli"),
        branding: .init(
            symbolName: "message.circle",
            accentColor: "#25D366",
            bundleIdentifier: "net.whatsapp.WhatsApp"),
        paths: .init(
            defaultConfig: "~/.wacli/config.yaml",
            defaultDatabase: "~/.wacli/wacli.db",
            defaultCache: "~/.wacli",
            defaultLogs: "~/.wacli/logs",
            defaultShare: "~/.wacli/share"),
        commands: [
            "status": ["--account", "{config:account}", "--read-only", "--json", "doctor"],
            "doctor": ["--account", "{config:account}", "--read-only", "--json", "doctor"],
            "refresh": ["--account", "{config:account}", "--json", "sync", "--once"],
            "search": ["--account", "{config:account}", "--read-only", "--json", "messages", "search"],
        ],
        capabilities: [.status, .doctor, .refresh, .search],
        statusRequiresSecrets: false,
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false, localOnlyScopes: ["WhatsApp chats", "contacts", "messages"]),
        configOptions: [
            .init(id: "execution_mode", label: "Run location", kind: .choice, help: "Run wacli on this Mac or over SSH on another machine.", defaultValue: "local", choices: ["local", "remote"]),
            .init(id: "remote_target", label: "SSH target", help: "SSH target that can run wacli, for example user@example-host.", placeholder: "user@example-host"),
            .init(id: "remote_run_as", label: "Run as user", help: "Optional remote Unix user for sudo -u, when wacli is installed under a service account.", placeholder: "crawl"),
            .init(id: "account", label: "wacli account", help: "Optional named account from the wacli config.", placeholder: "personal"),
        ],
        configSections: [
            .init(id: "execution", title: "Execution", optionIDs: ["execution_mode"]),
            .init(id: "remote", title: "Remote Host", optionIDs: ["remote_target", "remote_run_as"]),
            .init(id: "whatsapp", title: "WhatsApp Account", optionIDs: ["account"]),
        ],
        install: .init(method: .homebrew, package: "openclaw/tap/wacli"))
        .withSuggestion(Self.appSuggest("WhatsApp", ["net.whatsapp.WhatsApp"]))
}
