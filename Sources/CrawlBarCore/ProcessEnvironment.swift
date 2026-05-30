import Foundation

public enum CrawlProcessEnvironment {
    public static func normalized(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var normalized = environment
        normalized["HOME"] = environment["HOME"]?.nilIfBlank ?? FileManager.default.homeDirectoryForCurrentUser.path
        normalized["PATH"] = self.path(environment: environment)
        return normalized
    }

    public static func path(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        self.pathEntries(environment: environment).joined(separator: ":")
    }

    public static func pathEntries(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var seen: Set<String> = []
        var entries: [String] = []

        for entry in (environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: true).map(String.init) {
            self.append(entry, to: &entries, seen: &seen)
        }

        for entry in self.defaultExecutableSearchPaths(environment: environment) {
            self.append(entry, to: &entries, seen: &seen)
        }

        return entries
    }

    private static func defaultExecutableSearchPaths(environment: [String: String]) -> [String] {
        var paths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        if let home = environment["HOME"]?.nilIfBlank ?? FileManager.default.homeDirectoryForCurrentUser.path.nilIfBlank {
            paths.insert("\(home)/.local/bin", at: 0)
            paths.insert("\(home)/bin", at: 1)
        }

        return paths
    }

    private static func append(_ path: String, to entries: inout [String], seen: inout Set<String>) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
        entries.append(trimmed)
    }
}
