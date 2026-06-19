import Foundation

public extension BuiltInCrawlApps {
    static let gitcrawl = CrawlAppManifest(
        id: Self.gitcrawlID,
        displayName: "GitHub",
        description: "Local GitHub issue and pull request archive",
        binary: .init(name: "gitcrawl"),
        branding: .init(
            symbolName: "point.3.connected.trianglepath.dotted",
            accentColor: "#24292F",
            bundleIdentifier: "com.github.GitHubClient"),
        paths: .init(
            defaultConfig: "~/.config/gitcrawl/config.toml",
            configEnv: "GITCRAWL_CONFIG",
            defaultDatabase: "~/.config/gitcrawl/gitcrawl.db",
            defaultCache: "~/.config/gitcrawl/cache",
            defaultLogs: "~/.config/gitcrawl/logs",
            defaultShare: "~/.config/gitcrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["status", "--json"],
            "doctor": ["doctor", "--json"],
            "refresh": ["sync", "--json"],
            "query": ["search", "--json"],
            "remote-status": ["remote", "status", "--json"],
            "remote-archives": ["remote", "archives", "--json"],
            "cloud-publish": ["cloud", "publish", "--json"],
        ],
        capabilities: [.status, .doctor, .refresh, .search, .remoteArchive, .cloudPublish],
        statusRequiresSecrets: false,
        privacy: .init(exportsSecrets: false, localOnlyScopes: ["repositories", "issues", "pull requests"]),
        configOptions: [
            .init(id: "github_token", label: "GitHub token", kind: .secret, help: "Token used for GitHub API refreshes.", placeholder: "ghp_...", envVar: "GITHUB_TOKEN", configKey: "github.token"),
            .init(id: "openai_api_key", label: "OpenAI API key", kind: .secret, help: "Used when Git Crawl generates embeddings.", placeholder: "sk-...", envVar: "OPENAI_API_KEY", configKey: "openai.api_key"),
            .init(id: "embedding_model", label: "Embedding model", kind: .choice, help: "Model used for local semantic indexing.", defaultValue: "text-embedding-3-small", choices: ["text-embedding-3-small", "text-embedding-3-large"], envVar: "OPENAI_EMBEDDING_MODEL", configKey: "embeddings.model"),
        ],
        configSections: [
            .init(id: "github", title: "GitHub Access", optionIDs: ["github_token"]),
            .init(id: "ai", title: "Embeddings", optionIDs: ["openai_api_key", "embedding_model"]),
        ],
        install: .init(method: .homebrew, package: "openclaw/tap/gitcrawl"))
        .withSuggestion(Self.alwaysSuggest("GitHub"))
}
