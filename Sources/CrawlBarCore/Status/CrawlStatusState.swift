import Foundation

public enum CrawlAppState: String, Codable, Equatable, Sendable {
    case current
    case stale
    case syncing
    case needsConfig = "needs_config"
    case needsAuth = "needs_auth"
    case error
    case disabled
    case unknown
}

public struct CrawlCount: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var value: Int

    public init(id: String, label: String, value: Int) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct CrawlFreshness: Codable, Equatable, Sendable {
    public var status: CrawlAppState
    public var ageSeconds: Int?
    public var staleAfterSeconds: Int?

    public init(status: CrawlAppState, ageSeconds: Int? = nil, staleAfterSeconds: Int? = nil) {
        self.status = status
        self.ageSeconds = ageSeconds
        self.staleAfterSeconds = staleAfterSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case ageSeconds = "age_seconds"
        case staleAfterSeconds = "stale_after_seconds"
    }
}
