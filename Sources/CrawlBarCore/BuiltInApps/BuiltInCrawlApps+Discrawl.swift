import Foundation

public extension BuiltInCrawlApps {
    static let discrawl = CrawlAppManifest(
        id: Self.discrawlID,
        displayName: "Discord",
        description: "Local Discord guild and desktop-cache archive",
        binary: .init(name: "discrawl"),
        branding: .init(
            symbolName: "antenna.radiowaves.left.and.right",
            accentColor: "#5865F2",
            bundleIdentifier: "com.hnc.Discord"),
        paths: .init(
            defaultConfig: "~/.discrawl/config.toml",
            configEnv: "DISCRAWL_CONFIG",
            defaultDatabase: "~/.discrawl/discrawl.db",
            defaultCache: "~/.discrawl/cache",
            defaultLogs: "~/.discrawl/logs",
            defaultShare: "~/.discrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["status", "--json"],
            "doctor": ["doctor", "--json"],
            "refresh": ["--json", "cache-import"],
            "desktop-cache-import": ["--json", "cache-import"],
            "publish": ["--json", "publish"],
            "update": ["--json", "update"],
            "remote-status": ["remote", "status", "--json"],
            "remote-archives": ["remote", "archives", "--json"],
            "cloud-publish": ["cloud", "publish", "--sqlite-only", "--json"],
        ],
        capabilities: [.status, .doctor, .refresh, .publish, .subscribe, .update, .desktopCache, .remoteArchive, .cloudPublish],
        statusRequiresSecrets: false,
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false, localOnlyScopes: ["@me"]),
        configOptions: [
            .init(id: "discord_token", label: "Discord token", kind: .secret, help: "Token for Discord API or desktop-cache assisted sync.", placeholder: "token", envVar: "DISCORD_TOKEN", configKey: "discord.token"),
            .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, help: "Used when Discord Crawl generates embeddings.", placeholder: "sk-...", envVar: "OPENAI_API_KEY", configKey: "openai.api_key"),
            .init(id: "embedding_model", label: "Embedding model", kind: .choice, defaultValue: "text-embedding-3-small", choices: ["text-embedding-3-small", "text-embedding-3-large"], envVar: "OPENAI_EMBEDDING_MODEL", configKey: "embeddings.model"),
        ],
        configSections: [
            .init(id: "discord", title: "Discord Access", optionIDs: ["discord_token"]),
            .init(id: "ai", title: "Embeddings", optionIDs: ["openai_api_key", "embedding_model"]),
        ],
        install: .init(method: .homebrew, package: "vincentkoc/tap/discrawl"))
}
