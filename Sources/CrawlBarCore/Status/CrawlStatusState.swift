import Foundation

package enum CrawlAppState: String, Codable, Equatable, Sendable {
    case current
    case stale
    case syncing
    case needsConfig = "needs_config"
    case needsAuth = "needs_auth"
    case error
    case disabled
    case unknown
}

package struct CrawlCount: Codable, Equatable, Sendable, Identifiable {
    package var id: String
    package var label: String
    package var value: Int

    package init(id: String, label: String, value: Int) {
        self.id = id
        self.label = label
        self.value = value
    }
}

package struct CrawlFreshness: Codable, Equatable, Sendable {
    package var status: CrawlAppState
    package var ageSeconds: Int?
    package var staleAfterSeconds: Int?

    package init(status: CrawlAppState, ageSeconds: Int? = nil, staleAfterSeconds: Int? = nil) {
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
