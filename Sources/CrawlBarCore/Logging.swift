import OSLog

public enum CrawlBarLog {
    public static let app = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "app")
    public static let config = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "config")
    public static let keychain = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "keychain")
    public static let actions = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "actions")
    public static let status = Logger(subsystem: "com.vincentkoc.CrawlBar", category: "status")
}
