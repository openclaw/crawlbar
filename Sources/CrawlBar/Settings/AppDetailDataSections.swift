import CrawlBarCore
import Foundation
import SwiftUI

extension CrawlBarAppDetailView {
    var dataSection: some View {
        CrawlBarDetailSection(title: "Data") {
            self.remoteStore
            if !self.usesRemoteStore {
                self.databases
            }
            self.metrics
        }
    }

    @ViewBuilder
    var remoteStore: some View {
        if let remoteStore = self.remoteStoreSummary {
            CrawlBarPanel(title: remoteStore.title) {
                CrawlBarFact(label: "Remote", value: remoteStore.remote)
                if let archive = remoteStore.archive {
                    CrawlBarFact(label: "Archive", value: archive)
                }
                if let repoPath = remoteStore.repoPath {
                    CrawlBarFact(label: "Checkout", value: repoPath)
                }
                if let branch = remoteStore.branch {
                    CrawlBarFact(label: "Branch", value: branch)
                }
                if let bundle = remoteStore.bundle {
                    CrawlBarFact(label: "Bundle", value: bundle)
                }
                if let compressed = remoteStore.compressed {
                    CrawlBarFact(label: "Compressed", value: compressed)
                }
                if let parts = remoteStore.parts {
                    CrawlBarFact(label: "Parts", value: parts)
                }
                if let lastIngest = remoteStore.lastIngest {
                    CrawlBarFact(label: "Ingest", value: lastIngest)
                }
                if let databasePath = self.status?.databasePath {
                    CrawlBarFact(label: "Local index", value: URL(fileURLWithPath: databasePath).lastPathComponent)
                }
            }
        }
    }

    @ViewBuilder
    var databases: some View {
        if let databases = self.status?.databases, !databases.isEmpty {
            CrawlBarPanel(title: "Databases") {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        self.openDataFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open data folder")
                    Button {
                        self.backupDatabases()
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .buttonStyle(.borderless)
                    .disabled(self.runningAction != nil)
                    .accessibilityLabel("Back up database files")
                    Text("\(databases.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(spacing: 0) {
                    ForEach(databases) { database in
                        CrawlBarDatabaseRow(database: database)
                        if database.id != databases.last?.id {
                            Divider()
                                .padding(.leading, 28)
                        }
                    }
                }
            }
        } else {
            CrawlBarPanel(title: "Databases") {
                Label("No database metadata yet", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var metrics: some View {
        if !self.overviewCounts.isEmpty {
            CrawlBarPanel(title: "Counts") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Spacer(minLength: 0)
                    Text(self.overviewDataScope)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(self.overviewCounts) { count in
                        CrawlBarMetricRow(label: count.label, value: "\(count.value)")
                        if count.id != self.overviewCounts.last?.id {
                            Divider()
                        }
                    }
                }
            }
        } else {
            CrawlBarPanel(title: "Counts") {
                Label("No count metrics yet", systemImage: "number")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var archiveSourceSummary: String {
        if let remoteStore = self.remoteStoreSummary {
            return remoteStore.shortName
        }
        if let database = self.primaryDatabase ?? self.status?.databases.first {
            return database.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? database.label
        }
        if let databasePath = self.status?.databasePath ?? self.manifest?.paths.defaultDatabase {
            return URL(fileURLWithPath: databasePath).lastPathComponent
        }
        return "Unknown"
    }

    var databaseSummary: String {
        guard let status else { return "Unknown" }
        if let remoteStore = self.remoteStoreSummary {
            return remoteStore.databaseSummary
        }
        if self.app.id == BuiltInCrawlApps.gitcrawlID {
            return self.summaryText(label: "GitHub archives", bytes: self.totalDatabaseBytes)
        }
        if status.databases.count > 1 {
            return self.summaryText(label: "\(status.databases.count) databases", bytes: self.totalDatabaseBytes)
        }
        if let primaryDatabase = self.primaryDatabase ?? status.databases.first {
            let size = primaryDatabase.bytes ?? status.databaseBytes
            return self.summaryText(label: primaryDatabase.label, bytes: size)
        }
        return status.databasePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown"
    }

    var primaryDatabase: CrawlDatabaseResource? {
        self.status?.databases.first(where: { $0.isPrimary })
    }

    var totalDatabaseBytes: Int? {
        guard let status else { return nil }
        let total = status.databases.compactMap(\.bytes).reduce(0, +)
        if total > 0 { return total }
        return status.databaseBytes
    }

    var overviewCounts: [CrawlCount] {
        if let primaryCounts = self.primaryDatabase?.counts, !primaryCounts.isEmpty {
            return primaryCounts
        }
        let databaseCounts = self.totalCountsAcrossDatabases()
        if !databaseCounts.isEmpty {
            return databaseCounts
        }
        return self.status?.counts ?? []
    }

    var overviewDataScope: String {
        if let remoteStore = self.remoteStoreSummary {
            return remoteStore.dataScope
        }
        if self.primaryDatabase?.counts.isEmpty == false {
            return "Active database"
        }
        if let count = self.status?.databases.count, count > 1, !self.totalCountsAcrossDatabases().isEmpty {
            return "Total across \(count) databases"
        }
        return "Connected database"
    }

    func totalCountsAcrossDatabases() -> [CrawlCount] {
        let counts = self.status?.databases.flatMap(\.counts) ?? []
        guard !counts.isEmpty else { return [] }
        var labels: [String: String] = [:]
        var values: [String: Int] = [:]
        for count in counts {
            labels[count.id] = labels[count.id] ?? count.label
            values[count.id, default: 0] += count.value
        }
        return values.keys.sorted().map { id in
            CrawlCount(id: id, label: labels[id] ?? id, value: values[id] ?? 0)
        }
    }

    func summaryText(label: String, bytes: Int?) -> String {
        [
            label,
            bytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) },
        ].compactMap { $0?.nilIfBlank }.joined(separator: " · ")
    }

    func bundleSummary(_ bundle: CrawlSQLiteBundleStatus) -> String {
        [
            bundle.format?.nilIfBlank,
            bundle.compression?.nilIfBlank,
            bundle.compressedBytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) },
            bundle.partCount.map { "\($0) part\($0 == 1 ? "" : "s")" },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var usesRemoteStore: Bool {
        self.remoteStoreSummary != nil
    }

    var remoteStoreSummary: CrawlBarRemoteStoreSummary? {
        if let remote = self.status?.remote, remote.enabled {
            let database = self.status?.databases.first(where: { $0.endpoint != nil || $0.archive != nil })
            let endpoint = remote.endpoint?.nilIfBlank ?? database?.endpoint?.nilIfBlank ?? "Cloudflare remote"
            let archive = remote.archive?.nilIfBlank ?? database?.archive?.nilIfBlank
            return CrawlBarRemoteStoreSummary(
                remote: endpoint,
                archive: archive,
                kind: .cloudflare,
                sqliteBundle: self.status?.sqliteBundle,
                sqliteObject: self.status?.sqliteObject,
                lastIngestAt: remote.lastIngestAt ?? remote.lastSyncAt)
        }
        if self.status?.share?.enabled == true, let remote = self.status?.share?.remote?.nilIfBlank {
            return CrawlBarRemoteStoreSummary(
                remote: remote,
                repoPath: self.status?.share?.repoPath?.nilIfBlank,
                branch: self.status?.share?.branch?.nilIfBlank,
                kind: .gitSnapshot)
        }
        guard self.app.id == BuiltInCrawlApps.gitcrawlID else { return nil }
        var paths = self.status?.databases.compactMap(\.path) ?? []
        if let databasePath = self.status?.databasePath {
            paths.append(databasePath)
        }
        guard let storePath = paths.first(where: { $0.contains("/gitcrawl-store/") || $0.contains("/gitcrawl-store-remote/") }) else {
            return nil
        }
        let repoPath = Self.repoPath(containing: "/data/", in: storePath)
        return CrawlBarRemoteStoreSummary(
            remote: "https://github.com/openclaw/gitcrawl-store.git",
            repoPath: repoPath,
            branch: nil,
            kind: .gitSnapshot)
    }

    static func repoPath(containing marker: String, in path: String) -> String? {
        guard let range = path.range(of: marker) else { return nil }
        return String(path[..<range.lowerBound])
    }
}
