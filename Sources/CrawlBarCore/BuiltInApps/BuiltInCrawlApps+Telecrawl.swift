import Foundation

public extension BuiltInCrawlApps {
    static let telecrawl = CrawlAppManifest(
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
        .withSuggestion(Self.appSuggest("Telegram", ["ru.keepcoder.Telegram", "org.telegram.desktop"]))
}
