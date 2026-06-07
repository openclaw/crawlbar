import CrawlBarCore
import SwiftUI

enum CrawlBarSettingsSidebarItem: Hashable {
    case general
    case crawler(CrawlAppID)
}

struct CrawlBarCrawlerSection: Identifiable {
    let kind: CrawlBarCrawlerCategory
    let apps: [CrawlBarAppConfig]

    var id: CrawlBarCrawlerCategory { self.kind }
}

struct CrawlBarGeneralSidebarRow: View {
    let isSelected: Bool

    var body: some View {
        Label("General", systemImage: "gearshape")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(self.isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CrawlBarSidebarSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        if self.isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.82))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        } else {
            Color.clear
        }
    }
}

struct CrawlBarSidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(self.title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.top, 8)
    }
}

struct CrawlBarSidebarRow: View {
    let app: CrawlBarAppConfig
    let section: CrawlBarCrawlerCategory
    let manifest: CrawlAppManifest?
    let status: CrawlAppStatus?
    let binaryPath: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(CrawlBarCrawlerTitle.text(for: self.app.id, manifest: self.manifest))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(self.isSelected ? Color.white : Color.primary)
                        .lineLimit(1)
                    CrawlBarStatusDot(state: self.rowState)
                }
                Text(self.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(self.subtitleColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .opacity(self.manifest?.availability == .comingSoon ? 0.58 : 1)
    }

    private var rowState: CrawlAppState {
        if self.section != .my { return .disabled }
        if self.manifest?.availability == .comingSoon { return .disabled }
        if !self.app.enabled { return .disabled }
        if self.binaryPath == nil { return .needsConfig }
        let state = self.status?.state ?? .unknown
        if self.status?.isRecoverableGraincrawlSourceFailure == true {
            return .stale
        }
        return state
    }

    private var subtitle: String {
        let binaryName = self.manifest?.binary.name ?? self.app.id.rawValue
        if self.manifest?.availability == .comingSoon { return "\(binaryName) · coming soon" }
        if self.section == .suggested { return self.suggestedSubtitle }
        if self.section == .more { return self.moreSubtitle }
        if !self.app.enabled { return "Disabled" }
        if self.binaryPath == nil { return "Missing \(binaryName)" }
        if self.rowState == .needsAuth {
            return self.status?.summary ?? "Needs auth"
        }
        if self.rowState == .error {
            return self.status?.summary ?? "Error"
        }
        if self.rowState == .current,
           self.status?.freshness?.status == .stale
        {
            return "Status current"
        }
        if let syncedAt = self.syncedAt {
            return "Synced \(CrawlBarDateText.relative(syncedAt))"
        }
        switch self.rowState {
        case .syncing:
            return "Syncing"
        case .stale:
            return "Needs refresh"
        case .unknown:
            return "Waiting for status"
        default:
            return self.status == nil ? "Waiting for status" : "Status current"
        }
    }

    private var moreSubtitle: String {
        guard let suggestion = self.manifest?.suggestion,
              suggestion.kind == .app
        else {
            return "Not installed on this computer"
        }
        return "No \(suggestion.name) app found"
    }

    private var suggestedSubtitle: String {
        guard let suggestion = self.manifest?.suggestion else {
            return "Available crawler"
        }
        switch suggestion.kind {
        case .always:
            return "Available crawler"
        case .app:
            return "\(suggestion.name) is installed"
        }
    }

    private var syncedAt: Date? {
        if let lastSyncAt = self.status?.lastSyncAt {
            return lastSyncAt
        }
        if let primaryModifiedAt = self.status?.databases.first(where: { $0.isPrimary })?.modifiedAt {
            return primaryModifiedAt
        }
        return self.status?.databases.compactMap(\.modifiedAt).max()
    }

    private var subtitleColor: Color {
        if self.isSelected { return Color.white.opacity(0.78) }
        if self.section != .my { return Color.secondary }
        switch self.rowState {
        case .needsConfig, .needsAuth, .error:
            return Color.red
        case .stale where self.app.id == BuiltInCrawlApps.graincrawlID && self.status?.state == .error:
            return Color.yellow
        default:
            return Color.secondary
        }
    }
}
