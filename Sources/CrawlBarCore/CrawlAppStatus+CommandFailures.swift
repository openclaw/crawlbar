import Foundation

public extension CrawlAppStatus {
    var isRecoverableGraincrawlSourceFailure: Bool {
        guard self.appID == BuiltInCrawlApps.graincrawlID, self.state == .error else { return false }
        guard !Self.summaryLooksLikeActionFailure(self.summary) else { return false }
        let text = ([self.summary] + self.errors + self.warnings)
            .joined(separator: "\n")
            .lowercased()
        return text.contains("granola access token")
            || text.contains("unsupported cache version")
            || text.contains("private-api reports")
            || text.contains("desktop-cache reports")
    }

    func mergingActionFailure(_ failure: CrawlAppStatus) -> CrawlAppStatus {
        guard self.appID == failure.appID else { return failure }
        return CrawlAppStatus(
            schemaVersion: self.schemaVersion,
            appID: self.appID,
            generatedAt: failure.generatedAt,
            state: failure.state,
            summary: failure.summary,
            configPath: self.configPath,
            databasePath: self.databasePath,
            databaseBytes: self.databaseBytes,
            walBytes: self.walBytes,
            lastSyncAt: self.lastSyncAt,
            lastImportAt: self.lastImportAt,
            lastExportAt: self.lastExportAt,
            counts: self.counts,
            databases: self.databases,
            freshness: self.freshness,
            share: self.share,
            remote: self.remote,
            sqliteObject: self.sqliteObject,
            sqliteBundle: self.sqliteBundle,
            warnings: Self.mergedMessages(failure.warnings, self.warnings),
            errors: Self.mergedMessages(failure.errors, self.errors))
    }

    static func commandFailure(
        appID: CrawlAppID,
        action: String? = nil,
        message: String?,
        fallback: String)
        -> CrawlAppStatus
    {
        let fullMessage = message?.nilIfBlank ?? fallback
        let normalized = Self.normalizedCommandFailure(appID: appID, message: fullMessage)
        let summary = [action?.nilIfBlank, normalized.summary].compactMap { $0 }.joined(separator: ": ")
        return CrawlAppStatus(
            appID: appID,
            state: normalized.state,
            summary: summary,
            errors: [normalized.summary])
    }

    static func richestMetadataStatus(_ preferred: CrawlAppStatus?, fallback: CrawlAppStatus?) -> CrawlAppStatus? {
        guard let preferred else { return fallback }
        guard let fallback else { return preferred }
        return preferred.metadataScore >= fallback.metadataScore ? preferred : fallback
    }

    private var metadataScore: Int {
        var score = 0
        score += self.configPath == nil ? 0 : 1
        score += self.databasePath == nil ? 0 : 1
        score += self.databaseBytes == nil ? 0 : 1
        score += self.walBytes == nil ? 0 : 1
        score += self.lastSyncAt == nil ? 0 : 1
        score += self.lastImportAt == nil ? 0 : 1
        score += self.lastExportAt == nil ? 0 : 1
        score += self.counts.isEmpty ? 0 : 2
        score += self.databases.isEmpty ? 0 : 3
        score += self.freshness == nil ? 0 : 1
        score += self.share == nil ? 0 : 2
        score += self.remote == nil ? 0 : 3
        score += self.sqliteObject == nil ? 0 : 2
        score += self.sqliteBundle == nil ? 0 : 3
        return score
    }

    private static func mergedMessages(_ primary: [String], _ secondary: [String]) -> [String] {
        var seen = Set<String>()
        var messages: [String] = []
        for message in primary + secondary {
            guard !seen.contains(message) else { continue }
            seen.insert(message)
            messages.append(message)
        }
        return messages
    }

    private static func summaryLooksLikeActionFailure(_ summary: String) -> Bool {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "refresh:",
            "sync:",
            "desktop-cache-import:",
            "doctor:",
            "unlock:",
            "query:",
            "search:",
            "export-md:",
        ].contains { trimmed.hasPrefix($0) }
    }

    private static func normalizedCommandFailure(appID: CrawlAppID, message: String) -> (state: CrawlAppState, summary: String) {
        let lowered = message.lowercased()
        if appID == BuiltInCrawlApps.gitcrawlID,
           lowered.contains("github"),
           (lowered.contains("bad credentials") || lowered.contains("status 401") || lowered.contains("401"))
        {
            return (.needsAuth, "GitHub credentials rejected")
        }
        if appID == BuiltInCrawlApps.birdclawID,
           lowered.contains("no twitter cookies")
               || lowered.contains("no x cookies")
               || lowered.contains("missing credentials")
               || lowered.contains("missing auth_token")
               || lowered.contains("missing ct0")
        {
            return (.needsAuth, "X browser cookies not found")
        }
        if appID == BuiltInCrawlApps.gogcliID,
           lowered.contains("credentials") || lowered.contains("auth")
        {
            return (.needsAuth, "Google account needs auth")
        }
        return (.error, Self.firstUsefulFailureLine(in: message) ?? "Command failed")
    }

    private static func firstUsefulFailureLine(in message: String) -> String? {
        message.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                guard !line.isEmpty else { return false }
                return !Self.isRequestTraceLine(line)
            }
    }

    private static func isRequestTraceLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.hasPrefix("[github] request ")
            || lowered.hasPrefix("[slack] request ")
            || lowered.hasPrefix("[notion] request ")
            || lowered.hasPrefix("[discord] request ")
            || lowered.hasPrefix("[granola] request ")
    }
}
