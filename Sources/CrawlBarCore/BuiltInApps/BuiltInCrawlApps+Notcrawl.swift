import Foundation

public extension BuiltInCrawlApps {
    static let notcrawl = CrawlAppManifest(
        id: Self.notcrawlID,
        displayName: "Notion",
        description: "Local Notion archive with Markdown and table exports",
        binary: .init(name: "notcrawl"),
        branding: .init(
            symbolName: "doc.text.magnifyingglass",
            accentColor: "#111111",
            bundleIdentifier: "notion.id"),
        paths: .init(
            defaultConfig: "~/.notcrawl/config.toml",
            configEnv: "NOTCRAWL_CONFIG",
            defaultDatabase: "~/.notcrawl/notcrawl.db",
            defaultCache: "~/.notcrawl/cache",
            defaultLogs: "~/.notcrawl/logs",
            defaultShare: "~/.notcrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["status", "--json"],
            "doctor": ["doctor", "--json"],
            "refresh": ["sync", "--source", "desktop"],
            "desktop-cache-import": ["sync", "--source", "desktop"],
            "query": ["sql"],
            "search": ["search"],
            "export-md": ["export-md"],
            "publish": ["publish"],
            "update": ["update"],
        ],
        capabilities: [.status, .doctor, .refresh, .search, .publish, .subscribe, .update, .desktopCache, .exportMarkdown, .exportDatabase, .maintain],
        statusRequiresSecrets: false,
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false, localOnlyScopes: ["workspace pages", "comments", "exports"]),
        configOptions: [
            .init(id: "notion_token", label: "Notion token", kind: .secret, help: "Token or session credential for Notion sync.", placeholder: "secret_...", envVar: "NOTION_TOKEN", configKey: "notion.token"),
            .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, help: "Used when Notion Crawl generates embeddings.", placeholder: "sk-...", envVar: "OPENAI_API_KEY", configKey: "openai.api_key"),
            .init(id: "embedding_model", label: "Embedding model", kind: .choice, defaultValue: "text-embedding-3-small", choices: ["text-embedding-3-small", "text-embedding-3-large"], envVar: "OPENAI_EMBEDDING_MODEL", configKey: "embeddings.model"),
        ],
        configSections: [
            .init(id: "notion", title: "Notion Access", optionIDs: ["notion_token"]),
            .init(id: "ai", title: "Embeddings", optionIDs: ["openai_api_key", "embedding_model"]),
        ],
        install: .init(method: .homebrew, package: "openclaw/tap/notcrawl"))
        .withSuggestion(Self.appSuggest("Notion", ["notion.id"]))
}
