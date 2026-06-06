import Foundation

public struct CrawlShareStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var repoPath: String?
    public var remote: String?
    public var branch: String?
    public var needsUpdate: Bool?

    public init(enabled: Bool, repoPath: String? = nil, remote: String? = nil, branch: String? = nil, needsUpdate: Bool? = nil) {
        self.enabled = enabled
        self.repoPath = repoPath
        self.remote = remote
        self.branch = branch
        self.needsUpdate = needsUpdate
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case repoPath = "repo_path"
        case remote
        case branch
        case needsUpdate = "needs_update"
    }
}

public struct CrawlRemoteStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var mode: String?
    public var endpoint: String?
    public var archive: String?
    public var lastIngestAt: Date?
    public var lastSyncAt: Date?
    public var needsUpdate: Bool?

    public init(
        enabled: Bool,
        mode: String? = nil,
        endpoint: String? = nil,
        archive: String? = nil,
        lastIngestAt: Date? = nil,
        lastSyncAt: Date? = nil,
        needsUpdate: Bool? = nil)
    {
        self.enabled = enabled
        self.mode = mode
        self.endpoint = endpoint
        self.archive = archive
        self.lastIngestAt = lastIngestAt
        self.lastSyncAt = lastSyncAt
        self.needsUpdate = needsUpdate
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case endpoint
        case archive
        case lastIngestAt = "last_ingest_at"
        case lastSyncAt = "last_sync_at"
        case needsUpdate = "needs_update"
    }
}

public struct CrawlSQLiteObjectStatus: Codable, Equatable, Sendable {
    public var key: String?
    public var contentType: String?
    public var bytes: Int?
    public var uploadedAt: Date?

    public init(key: String? = nil, contentType: String? = nil, bytes: Int? = nil, uploadedAt: Date? = nil) {
        self.key = key
        self.contentType = contentType
        self.bytes = bytes
        self.uploadedAt = uploadedAt
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case contentType = "content_type"
        case bytes
        case uploadedAt = "uploaded_at"
    }
}

public struct CrawlSQLiteBundleStatus: Codable, Equatable, Sendable {
    public var key: String?
    public var contentType: String?
    public var format: String?
    public var compression: String?
    public var rawBytes: Int?
    public var compressedBytes: Int?
    public var partCount: Int?
    public var uploadedAt: Date?
    public var generatedAt: Date?

    public init(
        key: String? = nil,
        contentType: String? = nil,
        format: String? = nil,
        compression: String? = nil,
        rawBytes: Int? = nil,
        compressedBytes: Int? = nil,
        partCount: Int? = nil,
        uploadedAt: Date? = nil,
        generatedAt: Date? = nil)
    {
        self.key = key
        self.contentType = contentType
        self.format = format
        self.compression = compression
        self.rawBytes = rawBytes
        self.compressedBytes = compressedBytes
        self.partCount = partCount
        self.uploadedAt = uploadedAt
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case contentType = "content_type"
        case format
        case compression
        case rawBytes = "raw_bytes"
        case compressedBytes = "compressed_bytes"
        case partCount = "part_count"
        case uploadedAt = "uploaded_at"
        case generatedAt = "generated_at"
    }
}
