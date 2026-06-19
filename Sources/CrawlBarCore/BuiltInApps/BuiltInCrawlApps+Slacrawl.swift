import Foundation

public extension BuiltInCrawlApps {
    static let slacrawl = CrawlAppManifest(
        id: Self.slacrawlID,
        displayName: "Slack",
        description: "Local-first Slack workspace archive",
        binary: .init(name: "slacrawl"),
        branding: .init(
            symbolName: "bubble.left.and.bubble.right",
            accentColor: "#4A154B",
            bundleIdentifier: "com.tinyspeck.slackmacgap"),
        paths: .init(
            defaultConfig: "~/.slacrawl/config.toml",
            configEnv: "SLACRAWL_CONFIG",
            defaultDatabase: "~/.slacrawl/slacrawl.db",
            defaultCache: "~/.slacrawl/cache",
            defaultLogs: "~/.slacrawl/logs",
            defaultShare: "~/.slacrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["status", "--json"],
            "doctor": ["doctor", "--json"],
            "refresh": ["--json", "sync", "--source", "desktop"],
            "desktop-cache-import": ["--json", "sync", "--source", "desktop"],
            "query": ["sql"],
            "search": ["--json", "search"],
            "publish": ["--json", "publish"],
            "update": ["--json", "update"],
        ],
        capabilities: [.status, .doctor, .refresh, .search, .publish, .subscribe, .update, .desktopCache],
        statusRequiresSecrets: false,
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false, localOnlyScopes: ["workspaces", "channels", "DMs"]),
        configOptions: [
            .init(id: "slack_token", label: "Slack token", kind: .secret, help: "User or bot token for Slack API sync.", placeholder: "xoxp- or xoxb-", envVar: "SLACK_TOKEN", configKey: "slack.token"),
            .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, help: "Used when Slack Crawl generates embeddings.", placeholder: "sk-...", envVar: "OPENAI_API_KEY", configKey: "openai.api_key"),
            .init(id: "embedding_model", label: "Embedding model", kind: .choice, defaultValue: "text-embedding-3-small", choices: ["text-embedding-3-small", "text-embedding-3-large"], envVar: "OPENAI_EMBEDDING_MODEL", configKey: "embeddings.model"),
        ],
        configSections: [
            .init(id: "slack", title: "Slack Access", optionIDs: ["slack_token"]),
            .init(id: "ai", title: "Embeddings", optionIDs: ["openai_api_key", "embedding_model"]),
        ],
        install: .init(method: .homebrew, package: "openclaw/tap/slacrawl"))
        .withSuggestion(Self.appSuggest("Slack", ["com.tinyspeck.slackmacgap"]))
}
