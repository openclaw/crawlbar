import Foundation

public final class CrawlExecutableResolver: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let lock = NSLock()
    private var resolvedExecutables: [String: String] = [:]

    public init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = CrawlProcessEnvironment.normalized(environment)
    }

    public func resolve(_ requestedPathOrName: String) -> String? {
        self.lock.lock()
        if let cached = self.resolvedExecutables[requestedPathOrName] {
            self.lock.unlock()
            if self.isExecutable(cached) {
                return cached
            }
            self.lock.lock()
            self.resolvedExecutables.removeValue(forKey: requestedPathOrName)
            self.lock.unlock()
        } else {
            self.lock.unlock()
        }

        let resolved = self.resolveUncached(requestedPathOrName)
        self.lock.lock()
        if let resolved {
            self.resolvedExecutables[requestedPathOrName] = resolved
        } else {
            self.resolvedExecutables.removeValue(forKey: requestedPathOrName)
        }
        self.lock.unlock()
        return resolved
    }

    private func resolveUncached(_ requestedPathOrName: String) -> String? {
        let expanded = PathExpander.expandHome(requestedPathOrName)
        if expanded.contains("/") {
            return self.isExecutable(expanded) ? expanded : nil
        }

        for entry in CrawlProcessEnvironment.pathEntries(environment: self.environment) {
            let candidate = URL(fileURLWithPath: entry)
                .appendingPathComponent(expanded)
                .path
            if self.isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func isExecutable(_ path: String) -> Bool {
        self.fileManager.isExecutableFile(atPath: path)
    }
}
