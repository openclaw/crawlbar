import Foundation

public enum BuiltInCrawlApps {
    public static let gitcrawlID = CrawlAppID(rawValue: "gitcrawl")
    public static let slacrawlID = CrawlAppID(rawValue: "slacrawl")
    public static let discrawlID = CrawlAppID(rawValue: "discrawl")
    public static let telecrawlID = CrawlAppID(rawValue: "telecrawl")
    public static let imsgcrawlID = CrawlAppID(rawValue: "imsgcrawl")
    public static let photoscrawlID = CrawlAppID(rawValue: "photoscrawl")
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
        Self.imsgcrawl,
        Self.photoscrawl,
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

    static func alwaysSuggest(_ name: String) -> CrawlAppManifest.Suggestion {
        .init(kind: .always, name: name)
    }

    static func appSuggest(_ name: String, _ bundleIDs: [String]) -> CrawlAppManifest.Suggestion {
        .init(kind: .app, name: name, bundleIDs: bundleIDs)
    }
}
