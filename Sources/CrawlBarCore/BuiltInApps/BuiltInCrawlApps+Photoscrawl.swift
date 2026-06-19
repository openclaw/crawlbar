import Foundation

public extension BuiltInCrawlApps {
    static let photoscrawl = CrawlAppManifest(
        id: Self.photoscrawlID,
        displayName: "Apple Photos",
        description: "Local-first, read-only Apple Photos archive crawler",
        availability: .comingSoon,
        binary: .init(name: "photoscrawl"),
        branding: .init(
            symbolName: "photo.on.rectangle.angled",
            accentColor: "#FF2D55",
            bundleIdentifier: "com.apple.Photos"),
        paths: .init(
            defaultConfig: "~/Library/Application Support/photoscrawl/config.toml",
            defaultDatabase: "~/Library/Application Support/photoscrawl/photos.sqlite",
            defaultCache: "~/Library/Caches/photoscrawl",
            defaultLogs: "~/Library/Application Support/photoscrawl/logs",
            defaultShare: "~/Library/Application Support/photoscrawl/share"),
        commands: [
            "metadata": ["metadata", "--json"],
            "status": ["status", "--json"],
            "refresh": ["crawl", "--library", "{config:library_path}", "--json"],
            "query": ["search", "--json", "--query"],
        ],
        capabilities: [.status, .refresh, .search],
        statusRequiresSecrets: false,
        privacy: .init(
            exportsSecrets: false,
            localOnlyScopes: [
                "apple-photos",
                "sqlite",
                "media-metadata",
                "location-observations",
                "local-model-observations",
            ]),
        configOptions: [
            .init(
                id: "library_path",
                label: "Photos library",
                help: "Photos Library package read by refresh; photoscrawl expands a leading ~/ path.",
                defaultValue: "~/Pictures/Photos Library.photoslibrary"),
        ],
        configSections: [
            .init(id: "photos", title: "Photos Library", optionIDs: ["library_path"]),
        ])
        .withSuggestion(Self.appSuggest("Photos", ["com.apple.Photos"]))
}
