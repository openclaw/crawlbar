import Foundation

final class CrawlBarConfigCache: @unchecked Sendable {
    static let shared = CrawlBarConfigCache()

    private struct Entry {
        var modificationDate: Date?
        var config: CrawlBarConfig
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    init() {}

    func config(path: String, modificationDate: Date?) -> CrawlBarConfig? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let entry = self.entries[path], entry.modificationDate == modificationDate else {
            return nil
        }
        return entry.config
    }

    func set(_ config: CrawlBarConfig, path: String, modificationDate: Date?) {
        self.lock.lock()
        self.entries[path] = Entry(modificationDate: modificationDate, config: config)
        self.lock.unlock()
    }
}
