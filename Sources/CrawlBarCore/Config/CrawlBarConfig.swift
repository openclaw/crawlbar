import Foundation

public struct CrawlBarConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 3

    public var version: Int
    public var refreshFrequency: RefreshFrequency
    public var manifestDirectories: [String]
    public var apps: [CrawlBarAppConfig]

    public init(
        version: Int = Self.currentVersion,
        refreshFrequency: RefreshFrequency = .fifteenMinutes,
        manifestDirectories: [String] = ["~/.crawlbar/apps"],
        apps: [CrawlBarAppConfig] = [])
    {
        self.version = version
        self.refreshFrequency = refreshFrequency
        self.manifestDirectories = manifestDirectories
        self.apps = apps
    }

    public func normalized(knownIDs: [CrawlAppID] = BuiltInCrawlApps.all.map(\.id)) -> CrawlBarConfig {
        var seen: Set<CrawlAppID> = []
        var normalizedApps: [CrawlBarAppConfig] = []
        for var app in self.apps where !seen.contains(app.id) {
            seen.insert(app.id)
            if BuiltInCrawlApps.manifest(for: app.id)?.availability == .comingSoon {
                app.enabled = false
                app.showInMenuBar = false
                app.autoRefreshEnabled = false
                app.shareEnabled = false
                app.shareAfterRefresh = false
            } else if Self.shouldEnableNewlyAvailableApp(id: app.id, fromVersion: self.version),
                      !app.enabled, !app.showInMenuBar
            {
                app.enabled = true
                app.showInMenuBar = true
            }
            normalizedApps.append(app)
        }
        for id in knownIDs where !seen.contains(id) {
            let enabled = BuiltInCrawlApps.manifest(for: id)?.availability != .comingSoon
            normalizedApps.append(CrawlBarAppConfig(id: id, enabled: enabled, showInMenuBar: enabled))
        }
        return CrawlBarConfig(
            version: Self.currentVersion,
            refreshFrequency: self.refreshFrequency,
            manifestDirectories: self.manifestDirectories.isEmpty ? ["~/.crawlbar/apps"] : self.manifestDirectories,
            apps: normalizedApps)
    }

    public func appConfig(for id: CrawlAppID) -> CrawlBarAppConfig? {
        self.apps.first { $0.id == id }
    }

    private static let newlyAvailableV2AppIDs: Set<CrawlAppID> = [
        BuiltInCrawlApps.gogcliID,
        BuiltInCrawlApps.wacliID,
    ]

    private static let newlyAvailableV3AppIDs: Set<CrawlAppID> = [
        BuiltInCrawlApps.birdclawID,
    ]

    private static func shouldEnableNewlyAvailableApp(id: CrawlAppID, fromVersion version: Int) -> Bool {
        (version < 2 && Self.newlyAvailableV2AppIDs.contains(id))
            || (version < 3 && Self.newlyAvailableV3AppIDs.contains(id))
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case refreshFrequency = "refresh_frequency"
        case manifestDirectories = "manifest_directories"
        case apps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        self.refreshFrequency = try container.decodeIfPresent(RefreshFrequency.self, forKey: .refreshFrequency) ?? .fifteenMinutes
        self.manifestDirectories = try container.decodeIfPresent([String].self, forKey: .manifestDirectories) ?? ["~/.crawlbar/apps"]
        self.apps = try container.decodeIfPresent([CrawlBarAppConfig].self, forKey: .apps) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.refreshFrequency, forKey: .refreshFrequency)
        try container.encode(self.manifestDirectories, forKey: .manifestDirectories)
        try container.encode(self.apps, forKey: .apps)
    }
}
