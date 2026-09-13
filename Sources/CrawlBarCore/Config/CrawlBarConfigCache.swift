import Foundation

public final class CrawlBarConfigCache: @unchecked Sendable {
    public static let shared = CrawlBarConfigCache()

    private struct Entry {
        var modificationDate: Date?
        var config: CrawlBarConfig
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    func config(path: String, modificationDate: Date?) -> CrawlBarConfig? {
        self.lock.withLock {
            guard let entry = self.entries[path], entry.modificationDate == modificationDate else {
                return nil
            }
            return entry.config
        }
    }

    func set(_ config: CrawlBarConfig, path: String, modificationDate: Date?) {
        self.lock.withLock {
            self.entries[path] = Entry(modificationDate: modificationDate, config: config)
        }
    }
}
