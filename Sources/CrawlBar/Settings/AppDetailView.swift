import CrawlBarCore
import SwiftUI

struct CrawlBarAppDetailView: View {
    @Binding var app: CrawlBarAppConfig
    let globalRefreshFrequency: RefreshFrequency
    let installation: CrawlAppInstallation?
    let status: CrawlAppStatus?
    let latestResult: CrawlCommandResult?
    let isRefreshing: Bool
    let runningAction: String?
    let actionMessage: String?
    let refreshStatus: () -> Void
    let runAction: (String) -> Void
    let installApp: () -> Void
    let backupDatabases: () -> Void
    let openDataFolder: () -> Void
    let configValueChanged: (CrawlAppManifest.ConfigOption, String?) -> Void
    let save: () -> Void
    let saveDebounced: () -> Void

    var manifest: CrawlAppManifest? { self.installation?.manifest ?? BuiltInCrawlApps.manifest(for: self.app.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.header
            if self.isComingSoon {
                self.comingSoonContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 6)
            } else if self.isMissingBinary {
                self.notInstalledContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        self.statusSection
                        self.dataSection
                        self.syncSection
                        self.configurationSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading)
    }

    var primaryIssue: String? {
        if let error = self.status?.errors.first?.nilIfBlank,
           !self.issueDuplicatesStatusSummary(error)
        {
            return error
        }
        if let warning = self.status?.warnings.first?.nilIfBlank,
           !self.issueDuplicatesStatusSummary(warning)
        {
            return warning
        }
        guard let latestResult, !latestResult.succeeded else { return nil }
        return latestResult.userFacingRunMessage ?? "\(Self.actionTitle(latestResult.action)) failed with exit \(latestResult.exitCode)"
    }

    func issueDuplicatesStatusSummary(_ issue: String) -> Bool {
        guard let summary = self.status?.summary.nilIfBlank else { return false }
        return summary.localizedCaseInsensitiveContains(issue)
    }

    var issueState: CrawlAppState {
        self.status?.isRecoverableGraincrawlSourceFailure == true ? .stale : .error
    }

    var refreshSourceSummary: String {
        if self.app.id == BuiltInCrawlApps.gitcrawlID {
            return "GitHub API (remote)"
        }
        if self.app.id == BuiltInCrawlApps.graincrawlID {
            switch self.app.configValues["preferred_source"]?.nilIfBlank ?? "private-api" {
            case "desktop-cache":
                return "Granola desktop cache"
            case "private-api":
                return "Granola private API (remote)"
            default:
                return self.app.configValues["preferred_source"] ?? "Granola source"
            }
        }
        if self.manifest?.capabilities.contains(.desktopCache) == true {
            return "Desktop cache (local)"
        }
        if self.manifest?.capabilities.contains(.refresh) == true {
            return "Crawler CLI"
        }
        return "Not available"
    }

    var snapshotSummary: String {
        guard self.app.shareEnabled else { return "Off" }
        guard let share = self.status?.share else {
            return self.shareRepoPath == nil ? "Configured, not reported" : "Local snapshot"
        }
        let location = share.remote?.nilIfBlank ?? share.repoPath?.nilIfBlank ?? "Local snapshot"
        if let branch = share.branch?.nilIfBlank {
            return "\(location) · \(branch)"
        }
        return location
    }

    static func actionTitle(_ action: String) -> String {
        switch action {
        case "refresh":
            "Sync"
        case "doctor":
            "Doctor"
        case "unlock":
            "Unlock"
        case "publish":
            "Publish"
        case "cloud-publish":
            "Cloud Publish"
        case "remote-status":
            "Remote Status"
        case "remote-archives":
            "Remote Archives"
        case "update":
            "Update"
        case "desktop-cache-import":
            "Desktop Import"
        default:
            action
        }
    }

    var effectiveState: CrawlAppState {
        if self.isComingSoon { return .disabled }
        if !self.app.enabled { return .disabled }
        if self.installation?.binaryPath == nil { return .needsConfig }
        let state = self.status?.state ?? .unknown
        if self.status?.isRecoverableGraincrawlSourceFailure == true {
            return .stale
        }
        return state
    }

    var statusFallback: String {
        switch self.effectiveState {
        case .disabled where self.isComingSoon:
            "Coming soon"
        case .needsConfig:
            "\(self.manifest?.binary.name ?? self.app.id.rawValue) is not on PATH"
        case .disabled:
            "Disabled in CrawlBar"
        default:
            "Waiting for status"
        }
    }

    var binarySummary: String {
        if self.isComingSoon { return "Coming soon" }
        return self.installation?.binaryPath == nil ? "Missing" : "Found"
    }

    var lastSyncSummary: String {
        guard let date = self.lastSyncDate else { return "Never" }
        return "Synced \(CrawlBarDateText.relative(date))"
    }

    private var lastSyncDate: Date? {
        if let lastSyncAt = self.status?.lastSyncAt {
            return lastSyncAt
        }
        if let modifiedAt = self.primaryDatabase?.modifiedAt {
            return modifiedAt
        }
        return self.status?.databases.compactMap(\.modifiedAt).max()
    }
}
