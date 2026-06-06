import Foundation

public enum GitcrawlStatusSnapshot {
    public static func repository(for installation: CrawlAppInstallation) -> String? {
        guard installation.id == BuiltInCrawlApps.gitcrawlID else { return nil }
        if let databasePath = Self.configuredDatabasePath(for: installation),
           let repository = Self.repository(fromDatabasePath: databasePath)
        {
            return repository
        }
        if let databasePath = Self.configuredDatabasePath(for: installation) {
            return Self.adjacentReportURL(databasePath: databasePath).flatMap(Self.reportRepository)
        }
        if let databasePath = Self.defaultDatabasePath(for: installation),
           let repository = Self.repository(fromDatabasePath: databasePath)
        {
            return repository
        }
        return Self.reportContext(for: installation)?.repository
    }

    public static func status(for installation: CrawlAppInstallation) -> CrawlAppStatus? {
        guard installation.id == BuiltInCrawlApps.gitcrawlID else { return nil }
        guard let context = Self.reportContext(for: installation),
              let data = try? Data(contentsOf: context.reportURL),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let portable = object["portable"] as? [String: Any]
        let threads = portable?["threads"] as? [String: Any]
        let clusters = portable?["clusters"] as? [String: Any]
        let repository = object["repository"] as? [String: Any]
        let latestUpdatedAt = Self.date(threads?["latestUpdatedAt"])
        let totalThreads = Self.int(threads?["total"])
        let openThreads = Self.int(threads?["open"])
        let clusterGroups = Self.int(clusters?["groups"])

        let counts = [
            totalThreads.map { CrawlCount(id: "threads", label: "Threads", value: $0) },
            openThreads.map { CrawlCount(id: "open_threads", label: "Open Threads", value: $0) },
            clusterGroups.map { CrawlCount(id: "clusters", label: "Clusters", value: $0) },
            repository == nil ? nil : CrawlCount(id: "repositories", label: "Repositories", value: 1),
        ].compactMap { $0 }

        let staleAfterSeconds = installation.staleAfterSeconds ?? 86_400
        let state: CrawlAppState = latestUpdatedAt.map {
            Date().timeIntervalSince($0) > TimeInterval(staleAfterSeconds) ? .stale : .current
        } ?? .current
        let freshness = latestUpdatedAt.map {
            let ageSeconds = max(0, Int(Date().timeIntervalSince($0)))
            return CrawlFreshness(
                status: ageSeconds > staleAfterSeconds ? .stale : .current,
                ageSeconds: ageSeconds,
                staleAfterSeconds: staleAfterSeconds)
        }

        let status = CrawlAppStatus(
            appID: installation.id,
            state: state,
            summary: Self.summary(counts: counts),
            configPath: Self.configPath(for: installation)?.path,
            databasePath: context.databasePath,
            lastSyncAt: latestUpdatedAt,
            counts: counts,
            freshness: freshness)
        return CrawlDatabaseInventory.enrich(status, manifest: installation.manifest)
    }

    private static func summary(counts: [CrawlCount]) -> String {
        let visible = counts.prefix(2).map { "\($0.value) \($0.label.lowercased())" }
        return visible.isEmpty ? "Git Crawl status is current" : visible.joined(separator: ", ")
    }

    private struct ReportContext {
        var reportURL: URL
        var databasePath: String?
        var repository: String?
    }

    private static func reportContext(for installation: CrawlAppInstallation) -> ReportContext? {
        if let databasePath = Self.configuredDatabasePath(for: installation) {
            guard let reportURL = Self.adjacentReportURL(databasePath: databasePath) else { return nil }
            return ReportContext(
                reportURL: reportURL,
                databasePath: databasePath,
                repository: Self.repository(fromDatabasePath: databasePath) ?? Self.reportRepository(reportURL))
        }

        if let databasePath = Self.defaultDatabasePath(for: installation),
           let reportURL = Self.adjacentReportURL(databasePath: databasePath)
        {
            return ReportContext(
                reportURL: reportURL,
                databasePath: databasePath,
                repository: Self.repository(fromDatabasePath: databasePath) ?? Self.reportRepository(reportURL))
        }

        guard let reportURL = Self.latestStoreReportURL() else { return nil }
        let repository = Self.reportRepository(reportURL)
        return ReportContext(
            reportURL: reportURL,
            databasePath: Self.storeDatabasePath(reportURL: reportURL, repository: repository),
            repository: repository)
    }

    private static func latestStoreReportURL() -> URL? {
        let storesURL = URL(fileURLWithPath: PathExpander.expandHome("~/.config/gitcrawl/stores"), isDirectory: true)
        guard let storeURLs = try? FileManager.default.contentsOfDirectory(
            at: storesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return nil }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for storeURL in storeURLs {
            let reportURL = storeURL.appendingPathComponent("reports/latest-status.json")
            guard FileManager.default.fileExists(atPath: reportURL.path) else { continue }
            let values = try? reportURL.resourceValues(forKeys: [.contentModificationDateKey])
            candidates.append((reportURL, values?.contentModificationDate ?? .distantPast))
        }
        return candidates.sorted { $0.modifiedAt > $1.modifiedAt }.first?.url
    }

    private static func storeDatabasePath(reportURL: URL, repository: String?) -> String? {
        let storeURL = reportURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dataURL = storeURL.appendingPathComponent("data", isDirectory: true)
        if let repository {
            let filename = repository.replacingOccurrences(of: "/", with: "__") + ".sync.db"
            let databaseURL = dataURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: databaseURL.path) {
                return databaseURL.path
            }
        }
        let databaseURLs = (try? FileManager.default.contentsOfDirectory(
            at: dataURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return databaseURLs
            .filter { ["db", "sqlite", "sqlite3"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first?
            .path
    }

    private static func adjacentReportURL(databasePath: String) -> URL? {
        let databaseURL = URL(fileURLWithPath: databasePath)
        let reportURL = databaseURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("reports/latest-status.json")
        return FileManager.default.fileExists(atPath: reportURL.path) ? reportURL : nil
    }

    private static func reportRepository(_ reportURL: URL) -> String? {
        guard let data = try? Data(contentsOf: reportURL),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let repository = object["repository"] as? [String: Any]
        else { return nil }

        if let fullName = repository["fullName"] as? String ?? repository["full_name"] as? String,
           fullName.contains("/")
        {
            return fullName
        }
        if let owner = repository["owner"] as? String,
           let name = repository["name"] as? String
        {
            return "\(owner)/\(name)"
        }
        return nil
    }

    private static func repository(fromDatabasePath databasePath: String) -> String? {
        let filename = URL(fileURLWithPath: databasePath).lastPathComponent
        let stem = filename.replacingOccurrences(of: ".sync.db", with: "")
        let parts = stem.split(separator: "__", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    private static func configuredDatabasePath(for installation: CrawlAppInstallation) -> String? {
        if let configURL = Self.configPath(for: installation),
           let content = try? String(contentsOf: configURL, encoding: .utf8),
           let parsed = Self.tomlString("db_path", in: content)
        {
            return PathExpander.expandHome(parsed)
        }
        return nil
    }

    private static func defaultDatabasePath(for installation: CrawlAppInstallation) -> String? {
        return installation.manifest.paths.defaultDatabase.map { PathExpander.expandHome($0) }
    }

    private static func configPath(for installation: CrawlAppInstallation) -> URL? {
        if let override = installation.configPathOverride?.nilIfBlank {
            return URL(fileURLWithPath: PathExpander.expandHome(override))
        }
        if let envName = installation.manifest.paths.configEnv,
           let envValue = ProcessInfo.processInfo.environment[envName]?.nilIfBlank
        {
            return URL(fileURLWithPath: PathExpander.expandHome(envValue))
        }
        guard let defaultConfig = installation.manifest.paths.defaultConfig else { return nil }
        return URL(fileURLWithPath: PathExpander.expandHome(defaultConfig))
    }

    private static func tomlString(_ key: String, in content: String) -> String? {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let pieces = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            guard pieces[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            return pieces[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .nilIfBlank
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String, let trimmed = string.nilIfBlank else { return nil }
        return ISO8601DateFormatter.crawlBarDate(from: trimmed)
    }
}
