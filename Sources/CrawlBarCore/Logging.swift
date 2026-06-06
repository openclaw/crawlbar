import OSLog

package enum CrawlBarLog {
    package static let app = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "app")
    package static let config = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "config")
    package static let keychain = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "keychain")
    package static let actions = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "actions")
    package static let status = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "status")
}
