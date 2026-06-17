import Foundation

public extension BuiltInCrawlApps {
    static let imsgcrawl = CrawlAppManifest(
        id: Self.imsgcrawlID,
        displayName: "iMessage",
        description: "Local-first iMessage archive crawler",
        binary: .init(name: "imsgcrawl"),
        branding: .init(
            symbolName: "message.fill",
            accentColor: "#34C759",
            bundleIdentifier: "com.apple.MobileSMS"),
        paths: .init(
            defaultDatabase: "~/.imsgcrawl/archive.db",
            defaultCache: "~/.imsgcrawl/cache",
            defaultLogs: "~/.imsgcrawl/logs"),
        commands: [
            "metadata": ["--json", "metadata"],
            "status": ["--json", "status"],
            "refresh": ["--json", "sync"],
            "search": ["--json", "search"],
        ],
        capabilities: [.status, .refresh, .search],
        statusRequiresSecrets: false,
        privacy: .init(
            containsPrivateMessages: true,
            exportsSecrets: false,
            localOnlyScopes: [
                "apple-messages",
                "sqlite",
                "contact-handles",
                "message-archive",
                "message-text-search",
            ]))
        .withSuggestion(Self.appSuggest("Messages", ["com.apple.MobileSMS"]))
}
