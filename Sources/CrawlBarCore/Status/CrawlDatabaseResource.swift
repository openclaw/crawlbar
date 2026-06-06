import Foundation

package enum CrawlDatabaseKind: String, Codable, Equatable, Sendable {
    case sqlite
    case cache
    case logical
    case remote
    case d1
    case cloudflareD1 = "cloudflare-d1"
    case sqliteBundle = "sqlite_bundle"
}

package struct CrawlDatabaseResource: Codable, Equatable, Sendable, Identifiable {
    package var id: String
    package var label: String
    package var kind: CrawlDatabaseKind
    package var role: String?
    package var path: String?
    package var endpoint: String?
    package var archive: String?
    package var isPrimary: Bool
    package var bytes: Int?
    package var modifiedAt: Date?
    package var counts: [CrawlCount]

    package init(
        id: String,
        label: String,
        kind: CrawlDatabaseKind,
        role: String? = nil,
        path: String? = nil,
        endpoint: String? = nil,
        archive: String? = nil,
        isPrimary: Bool = false,
        bytes: Int? = nil,
        modifiedAt: Date? = nil,
        counts: [CrawlCount] = [])
    {
        self.id = id
        self.label = label
        self.kind = kind
        self.role = role
        self.path = path
        self.endpoint = endpoint
        self.archive = archive
        self.isPrimary = isPrimary
        self.bytes = bytes
        self.modifiedAt = modifiedAt
        self.counts = counts
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case kind
        case role
        case path
        case endpoint
        case archive
        case isPrimary = "is_primary"
        case bytes
        case modifiedAt = "modified_at"
        case counts
    }
}
