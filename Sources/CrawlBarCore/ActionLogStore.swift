import Foundation

public struct CrawlActionLogStore: @unchecked Sendable {
    public let directoryURL: URL
    private let fileManager: FileManager

    private static let maxRetainedLogCount = 200

    public init(
        directoryURL: URL = Self.defaultDirectory(),
        fileManager: FileManager = .default)
    {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public func save(_ result: CrawlCommandResult) throws -> URL {
        if !self.fileManager.fileExists(atPath: self.directoryURL.path) {
            try self.fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        }
        // Command results may derive from secret-bearing execution state.
        // Opaque names keep result fields out of filesystem metadata.
        let filename = UUID().uuidString + ".json"
        let url = self.directoryURL.appendingPathComponent(filename)
        let data = try CrawlCoding.makeJSONEncoder().encode(result)
        try data.write(to: url, options: [.atomic])
        #if os(macOS) || os(Linux)
        try self.fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path)
        #endif
        _ = self.retainedLogsNewestFirst()
        return url
    }

    public func recent(limit: Int = 20) -> [URL] {
        Array(self.retainedLogsNewestFirst().prefix(max(0, limit)))
    }

    public func recentResults(limit: Int = 20) -> [CrawlCommandResult] {
        self.recent(limit: limit).compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? CrawlCoding.makeJSONDecoder().decode(CrawlCommandResult.self, from: data)
        }
    }

    public static func defaultDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".crawlbar", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    private func retainedLogsNewestFirst() -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let urls = try? self.fileManager.contentsOfDirectory(
            at: self.directoryURL,
            includingPropertiesForKeys: Array(keys))
        else {
            return []
        }
        let sorted = urls
            .compactMap { url -> (URL, Date)? in
                // removeItem also deletes directories recursively. Only log files are eligible.
                guard url.pathExtension == "json",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      values.isSymbolicLink == false
                else { return nil }
                return (url, values.contentModificationDate ?? .distantPast)
            }
            .sorted {
                if $0.1 == $1.1 { return $0.0.lastPathComponent < $1.0.lastPathComponent }
                return $0.1 > $1.1
            }
        if sorted.count > Self.maxRetainedLogCount {
            for entry in sorted.dropFirst(Self.maxRetainedLogCount) {
                try? self.fileManager.removeItem(at: entry.0)
            }
        }
        return sorted.prefix(Self.maxRetainedLogCount).map(\.0)
    }

}
