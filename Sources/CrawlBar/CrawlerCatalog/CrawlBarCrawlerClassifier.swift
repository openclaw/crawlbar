import CrawlBarCore
import Foundation

enum CrawlBarCrawlerCategory: CaseIterable, Hashable {
    case my
    case suggested
    case more

    var title: String {
        switch self {
        case .my:
            "My Crawlers"
        case .suggested:
            "Suggested"
        case .more:
            "More Crawlers"
        }
    }
}

enum CrawlBarCrawlerClassifier {
    @MainActor
    static func category(
        app: CrawlBarAppConfig?,
        installation: CrawlAppInstallation?)
        -> CrawlBarCrawlerCategory
    {
        if self.isMyCrawler(app: app, installation: installation) {
            return .my
        }
        guard let installation, self.matchesSuggestion(installation: installation) else {
            return .more
        }
        return .suggested
    }

    nonisolated static func isMyCrawler(
        app: CrawlBarAppConfig?,
        installation: CrawlAppInstallation?)
        -> Bool
    {
        installation?.binaryPath != nil || self.hasUserCrawlerConfig(app)
    }

    nonisolated static func statusInstallations(
        _ installations: [CrawlAppInstallation],
        appConfigsByID: [CrawlAppID: CrawlBarAppConfig])
        -> [CrawlAppInstallation]
    {
        installations.filter { installation in
            guard installation.manifest.availability == .available else { return false }
            guard let config = appConfigsByID[installation.id], config.enabled else { return false }
            return self.isMyCrawler(app: config, installation: installation)
        }
    }

    @MainActor
    static func matchesSuggestion(installation: CrawlAppInstallation) -> Bool {
        guard let suggestion = installation.manifest.suggestion else { return false }
        switch suggestion.kind {
        case .always:
            return true
        case .app:
            return suggestion.bundleIDs.contains { bundleID in
                CrawlBarNativeAppLocator.url(for: bundleID) != nil
            }
        }
    }

    nonisolated private static func hasUserCrawlerConfig(_ app: CrawlBarAppConfig?) -> Bool {
        guard let app else { return false }
        return app.binaryPath?.nilIfBlank != nil
            || app.configPath?.nilIfBlank != nil
            || app.refreshFrequency != nil
            || app.autoRefreshEnabled
            || app.shareEnabled
            || app.shareAfterRefresh
            || app.preferredRefreshAction != "refresh"
            || app.preferredShareAction != "publish"
            || app.preferredUpdateAction != "update"
            || !app.configValues.isEmpty
    }
}
