import Foundation

package struct CrawlShareStatus: Codable, Equatable, Sendable {
    package var enabled: Bool
    package var repoPath: String?
    package var remote: String?
    package var branch: String?
    package var needsUpdate: Bool?

    package init(enabled: Bool, repoPath: String? = nil, remote: String? = nil, branch: String? = nil, needsUpdate: Bool? = nil) {
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

package struct CrawlRemoteStatus: Codable, Equatable, Sendable {
    package var enabled: Bool
    package var mode: String?
    package var endpoint: String?
    package var archive: String?
    package var lastIngestAt: Date?
    package var lastSyncAt: Date?
    package var needsUpdate: Bool?

    package init(
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

package struct CrawlSQLiteObjectStatus: Codable, Equatable, Sendable {
    package var key: String?
    package var contentType: String?
    package var bytes: Int?
    package var uploadedAt: Date?

    package init(key: String? = nil, contentType: String? = nil, bytes: Int? = nil, uploadedAt: Date? = nil) {
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

package struct CrawlSQLiteBundleStatus: Codable, Equatable, Sendable {
    package var key: String?
    package var contentType: String?
    package var format: String?
    package var compression: String?
    package var rawBytes: Int?
    package var compressedBytes: Int?
    package var partCount: Int?
    package var uploadedAt: Date?
    package var generatedAt: Date?

    package init(
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
