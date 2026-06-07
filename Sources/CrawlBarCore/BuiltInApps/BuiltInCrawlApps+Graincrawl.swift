import Foundation

public extension BuiltInCrawlApps {
    static let graincrawl = CrawlAppManifest(
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
        .withSuggestion(Self.appSuggest("Granola", ["com.granola.app"]))
}
