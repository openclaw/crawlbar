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
        if let cached = self.lock.withLock({ self.resolvedExecutables[requestedPathOrName] }) {
            if self.isExecutable(cached) {
                return cached
            }
            _ = self.lock.withLock { self.resolvedExecutables.removeValue(forKey: requestedPathOrName) }
        }

        let resolved = self.resolveUncached(requestedPathOrName)
        self.lock.withLock {
            self.resolvedExecutables[requestedPathOrName] = resolved
        }
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
