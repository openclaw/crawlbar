import Foundation

package enum BuiltInCrawlApps {
    package static let gitcrawlID = CrawlAppID(rawValue: "gitcrawl")
    package static let slacrawlID = CrawlAppID(rawValue: "slacrawl")
    package static let discrawlID = CrawlAppID(rawValue: "discrawl")
    package static let telecrawlID = CrawlAppID(rawValue: "telecrawl")
    package static let notcrawlID = CrawlAppID(rawValue: "notcrawl")
    package static let gogcliID = CrawlAppID(rawValue: "gogcli")
    package static let wacliID = CrawlAppID(rawValue: "wacli")
    package static let birdclawID = CrawlAppID(rawValue: "birdclaw")
    package static let graincrawlID = CrawlAppID(rawValue: "graincrawl")

    package static let all: [CrawlAppManifest] = [
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

    package static let allByID = Dictionary(uniqueKeysWithValues: Self.all.map { ($0.id, $0) })

    package static func manifest(for id: CrawlAppID) -> CrawlAppManifest? {
        self.allByID[id]
    }

    static func alwaysSuggest(_ name: String) -> CrawlAppManifest.Suggestion {
        .init(kind: .always, name: name)
    }

    static func appSuggest(_ name: String, _ bundleIDs: [String]) -> CrawlAppManifest.Suggestion {
        .init(kind: .app, name: name, bundleIDs: bundleIDs)
    }
}
