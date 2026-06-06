import Foundation

package extension CrawlAppManifest {
    struct Paths: Codable, Equatable, Sendable {
        package var defaultConfig: String?
        package var configEnv: String?
        package var defaultDatabase: String?
        package var defaultCache: String?
        package var defaultLogs: String?
        package var defaultShare: String?

        package init(
            defaultConfig: String? = nil,
            configEnv: String? = nil,
            defaultDatabase: String? = nil,
            defaultCache: String? = nil,
            defaultLogs: String? = nil,
            defaultShare: String? = nil)
        {
            self.defaultConfig = defaultConfig
            self.configEnv = configEnv
            self.defaultDatabase = defaultDatabase
            self.defaultCache = defaultCache
            self.defaultLogs = defaultLogs
            self.defaultShare = defaultShare
        }

        private enum CodingKeys: String, CodingKey {
            case defaultConfig = "default_config"
            case configEnv = "config_env"
            case defaultDatabase = "default_database"
            case defaultCache = "default_cache"
            case defaultLogs = "default_logs"
            case defaultShare = "default_share"
        }
    }
}
