import Foundation

public enum CrawlAppCapability: String, Codable, Equatable, Sendable, CaseIterable {
    case status
    case doctor
    case refresh
    case search
    case publish
    case subscribe
    case update
    case desktopCache = "desktop_cache"
    case exportMarkdown = "export_markdown"
    case exportDatabase = "export_database"
    case remoteArchive = "remote_archive"
    case cloudPublish = "cloud_publish"
    case maintain
}

public enum CrawlQueryActionResolver {
    public static func action(for manifest: CrawlAppManifest, queryArguments: [String]) -> String? {
        if Self.queryLooksLikeSQL(queryArguments) {
            return ["query", "sql"].first { manifest.commands[$0] != nil }
        }
        if manifest.commands["search"] != nil {
            return "search"
        }
        if manifest.commands["query"] != nil {
            return "query"
        }
        return nil
    }

    private static func queryLooksLikeSQL(_ arguments: [String]) -> Bool {
        let query = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["select ", "with ", "pragma ", "explain "].contains { query.hasPrefix($0) }
    }
}
