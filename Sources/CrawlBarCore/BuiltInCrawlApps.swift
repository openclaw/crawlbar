import Foundation

public enum BuiltInCrawlApps {
    public static let gitcrawlID = CrawlAppID(rawValue: "gitcrawl")
    public static let slacrawlID = CrawlAppID(rawValue: "slacrawl")
    public static let discrawlID = CrawlAppID(rawValue: "discrawl")
    public static let telecrawlID = CrawlAppID(rawValue: "telecrawl")
    public static let notcrawlID = CrawlAppID(rawValue: "notcrawl")
    public static let gogcliID = CrawlAppID(rawValue: "gogcli")
    public static let wacliID = CrawlAppID(rawValue: "wacli")
    public static let birdclawID = CrawlAppID(rawValue: "birdclaw")
    public static let graincrawlID = CrawlAppID(rawValue: "graincrawl")

    public static let all: [CrawlAppManifest] = [
        Self.gitcrawl,
        Self.slacrawl,
        Self.discrawl,
        Self.telecrawl,
        Self.notcrawl,
        Self.gogcli,
        Self.wacli,
        Self.birdclaw,
        Self.graincrawl,
    ]

    public static let allByID = Dictionary(uniqueKeysWithValues: Self.all.map { ($0.id, $0) })

    public static func manifest(for id: CrawlAppID) -> CrawlAppManifest? {
        self.allByID[id]
    }

    public static let gitcrawl = CrawlAppManifest(
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
        install: .init(method: .homebrew, package: "vincentkoc/tap/gitcrawl"))

    public static let slacrawl = CrawlAppManifest(
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
        install: .init(method: .homebrew, package: "vincentkoc/tap/slacrawl"))

    public static let discrawl = CrawlAppManifest(
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

    public static let telecrawl = CrawlAppManifest(
        id: Self.telecrawlID,
        displayName: "Telegram",
        description: "Local-first Telegram Desktop archive crawler",
        binary: .init(name: "telecrawl"),
        branding: .init(
            symbolName: "paperplane.fill",
            accentColor: "#229ED9",
            bundleIdentifier: "org.telegram.desktop"),
        paths: .init(
            defaultConfig: "~/.telecrawl/backup.json",
            defaultDatabase: "~/.telecrawl/telecrawl.db",
            defaultCache: "~/.telecrawl/cache",
            defaultLogs: "~/.telecrawl/logs"),
        commands: [
            "metadata": ["metadata"],
            "status": ["--json", "status"],
            "doctor": ["--json", "doctor"],
            "refresh": ["--json", "import"],
            "search": ["--json", "search"],
        ],
        capabilities: [.status, .doctor, .refresh, .search],
        statusRequiresSecrets: false,
        privacy: .init(
            containsPrivateMessages: true,
            exportsSecrets: false,
            localOnlyScopes: ["telegram-desktop", "sqlite", "encrypted-git-backup"]),
        install: .init(method: .homebrew, package: "steipete/tap/telecrawl"))

    public static let notcrawl = CrawlAppManifest(
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
        install: .init(method: .homebrew, package: "vincentkoc/tap/notcrawl"))

    public static let gogcli = CrawlAppManifest(
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

    public static let wacli = CrawlAppManifest(
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

    public static let birdclaw = CrawlAppManifest(
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

    public static let graincrawl = CrawlAppManifest(
        id: Self.graincrawlID,
        displayName: "Granola",
        description: "Local-first archive for Granola notes, transcripts, summaries, and panels",
        binary: .init(name: "graincrawl"),
        branding: .init(
            symbolName: "note.text",
            accentColor: "#D4A017",
            bundleIdentifier: "com.granola.app"),
        paths: .init(
            defaultConfig: "~/.config/graincrawl/config.toml",
            configEnv: "GRAINCRAWL_CONFIG",
            defaultDatabase: "~/.config/graincrawl/graincrawl.db",
            defaultCache: "~/.config/graincrawl/cache",
            defaultLogs: "~/.config/graincrawl/logs"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["status", "--json"],
            "doctor": ["doctor", "--json"],
            "unlock": ["unlock", "--json"],
            "refresh": ["sync", "--json"],
            "desktop-cache-import": ["sync", "--source", "desktop-cache", "--json"],
            "query": ["--json", "sql"],
            "search": ["--json", "search"],
            "export-md": ["export", "markdown", "--out", "./granola-notes"],
        ],
        capabilities: [.status, .doctor, .refresh, .search, .desktopCache, .exportMarkdown],
        statusRequiresSecrets: false,
        privacy: .init(containsPrivateMessages: true, exportsSecrets: false, localOnlyScopes: ["Granola profile", "graincrawl SQLite archive"]),
        configOptions: [
            .init(id: "granola_profile", label: "Granola profile", kind: .string, help: "Granola profile directory to inspect.", placeholder: "~/Library/Application Support/Granola", envVar: "GRAINCRAWL_GRANOLA_PROFILE", configKey: "granola.profile_path"),
            .init(id: "preferred_source", label: "Preferred source", kind: .choice, help: "Source used by refresh.", defaultValue: "private-api", choices: ["private-api", "desktop-cache"], envVar: "GRAINCRAWL_SOURCE", configKey: "granola.preferred_source"),
            .init(id: "allow_private_api", label: "Allow private API", kind: .boolean, defaultValue: "true", envVar: "GRAINCRAWL_ALLOW_PRIVATE_API", configKey: "granola.allow_private_api"),
            .init(id: "allow_desktop_cache", label: "Allow desktop cache", kind: .boolean, defaultValue: "true", configKey: "granola.allow_desktop_cache"),
            .init(id: "sync_limit", label: "Sync limit", kind: .number, help: "Maximum notes to import per sync run.", defaultValue: "100", configKey: "sync.default_limit"),
        ],
        configSections: [
            .init(id: "granola", title: "Granola", optionIDs: ["granola_profile", "preferred_source", "allow_private_api", "allow_desktop_cache"]),
            .init(id: "sync", title: "Sync", optionIDs: ["sync_limit"]),
        ],
        install: .init(method: .homebrew, package: "vincentkoc/tap/graincrawl"))
}
