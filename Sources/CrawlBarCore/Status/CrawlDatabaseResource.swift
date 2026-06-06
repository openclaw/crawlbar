import Foundation

public enum CrawlDatabaseKind: String, Codable, Equatable, Sendable {
    case sqlite
    case cache
    case logical
    case remote
    case d1
    case cloudflareD1 = "cloudflare-d1"
    case sqliteBundle = "sqlite_bundle"
}

public struct CrawlDatabaseResource: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var kind: CrawlDatabaseKind
    public var role: String?
    public var path: String?
    public var endpoint: String?
    public var archive: String?
    public var isPrimary: Bool
    public var bytes: Int?
    public var modifiedAt: Date?
    public var counts: [CrawlCount]

    public init(
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
