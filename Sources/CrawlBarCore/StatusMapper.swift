import Foundation

public struct CrawlStatusMapper: Sendable {
    static let defaultStaleAfterSeconds = 86_400

    public init() {}

    public func status(
        from result: CrawlCommandResult,
        manifest: CrawlAppManifest,
        staleAfterSeconds: Int? = nil)
        -> CrawlAppStatus
    {
        guard result.succeeded else {
            return CrawlAppStatus.commandFailure(
                appID: result.appID,
                message: result.stderr.nilIfBlank ?? result.stdout.nilIfBlank,
                fallback: "Command failed with exit \(result.exitCode)")
        }

        guard let object = self.parseObject(result.stdout) else {
            if manifest.id == BuiltInCrawlApps.birdclawID {
                return self.birdStatusText(result)
            }
            return CrawlAppStatus(
                appID: result.appID,
                state: .unknown,
                summary: result.stdout.nilIfBlank ?? "Command succeeded without JSON output",
                warnings: ["Status command did not return parseable JSON"])
        }

        let status: CrawlAppStatus
        if self.isCrawlKitStatus(object) {
            status = self.genericStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
        } else {
            switch manifest.id {
            case BuiltInCrawlApps.gitcrawlID:
                status = self.gitcrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.slacrawlID:
                status = self.slacrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.discrawlID:
                status = self.discrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.telecrawlID:
                status = self.telecrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.notcrawlID:
                status = self.notcrawlStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.gogcliID:
                status = self.gogcliStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.wacliID:
                status = self.wacliStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
            case BuiltInCrawlApps.birdclawID:
                status = self.birdclawStatus(object, result: result)
            default:
                if self.isWacliManifest(manifest) {
                    status = self.wacliStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
                } else {
                    status = self.genericStatus(object, result: result, staleAfterSeconds: staleAfterSeconds)
                }
            }
        }
        return CrawlDatabaseInventory.enrich(status, manifest: manifest)
    }
}
