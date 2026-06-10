import AppKit
import CrawlBarCore
import SwiftUI

struct CrawlBarPermissionsSettingsView: View {
    @ObservedObject var model: CrawlBarSettingsModel

    private var requirements: [CrawlBarPermissionRequirement] {
        CrawlBarPermissionRequirement.installedRequirements(model: self.model)
    }

    private var fullDiskAccessRequirement: CrawlBarPermissionRequirement? {
        self.requirements.first { $0.id == "full_disk_access" }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: CrawlBarSettingsLayout.sectionSpacing) {
                    self.header
                    if self.requirements.isEmpty {
                        ContentUnavailableView(
                            "No Permissions Required",
                            systemImage: "hand.raised",
                            description: Text("Installed crawlers have not declared macOS permissions."))
                            .frame(maxWidth: .infinity, minHeight: CrawlBarSettingsLayout.emptyStateMinHeight)
                    } else {
                        self.permissionList
                    }
                    Spacer(minLength: CrawlBarSettingsLayout.sectionSpacing)
                    if let requirement = self.fullDiskAccessRequirement,
                       requirement.permissionState != .allowed
                    {
                        self.fullDiskAccessHelp
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                .padding(.bottom, CrawlBarSettingsLayout.detailBottomPadding)
            }
        }
        .padding(.horizontal, CrawlBarSettingsLayout.detailHorizontalPadding)
        .padding(.vertical, CrawlBarSettingsLayout.detailVerticalPadding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CrawlBarSettingsLayout.labelSpacing) {
            Text("Permissions")
                .font(.title2.weight(.semibold))
            Text("Required by installed crawlers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionList: some View {
        VStack(spacing: .zero) {
            ForEach(Array(self.requirements.enumerated()), id: \.element.id) { index, requirement in
                CrawlBarPermissionRow(requirement: requirement)
                if index < self.requirements.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullDiskAccessHelp: some View {
        CrawlBarPanel {
            VStack(alignment: .leading, spacing: CrawlBarSettingsLayout.panelContentSpacing) {
                CrawlBarControlRow(
                    title: "Allow Full Disk Access",
                    caption: "Drag CrawlBar to the app list in System Settings to allow Full Disk Access.")
                {
                    Button {
                        self.model.openPermissionSettings(permissionID: "full_disk_access")
                    } label: {
                        Label("Open System Settings...", systemImage: "gearshape")
                    }
                    .controlSize(.small)
                }
                CrawlBarDraggableAppItem(bundleURL: Bundle.main.bundleURL)
            }
        }
    }
}

private struct CrawlBarPermissionRequirement: Identifiable {
    let permission: CrawlAppManifest.Permission
    let crawlers: [CrawlBarPermissionCrawler]
    let permissionState: CrawlBarPermissionState

    var id: String { self.permission.id }

    var title: String { self.permission.label }

    var symbolName: String {
        switch self.id {
        case "full_disk_access":
            "internaldrive"
        case "contacts":
            "person.crop.circle"
        case "photos":
            "photo"
        case "calendars":
            "calendar"
        case "reminders":
            "checklist"
        default:
            "hand.raised"
        }
    }

    @MainActor
    static func installedRequirements(model: CrawlBarSettingsModel) -> [Self] {
        let installedApps = model.crawlerSections.first { $0.kind == .my }?.apps ?? []
        var grouped: [String: (permission: CrawlAppManifest.Permission, crawlers: [CrawlBarPermissionCrawler])] = [:]

        for app in installedApps {
            guard let manifest = model.installations[app.id]?.manifest else { continue }
            let crawler = CrawlBarPermissionCrawler(appID: app.id, manifest: manifest)
            for permission in manifest.permissions {
                let current = grouped[permission.id]
                grouped[permission.id] = (
                    permission: current?.permission ?? permission,
                    crawlers: (current?.crawlers ?? []) + [crawler])
            }
        }

        return grouped.values
            .map { entry in
                let crawlers = entry.crawlers.sorted()
                return Self(
                    permission: entry.permission,
                    crawlers: crawlers,
                    permissionState: CrawlBarPermissionState.resolve(crawlers: crawlers, statuses: model.statuses))
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

private enum CrawlBarPermissionState: Equatable {
    case allowed
    case blocked
    case unknown

    var label: String {
        switch self {
        case .allowed:
            "Allowed"
        case .blocked:
            "Blocked"
        case .unknown:
            "Unknown"
        }
    }

    var appState: CrawlAppState {
        switch self {
        case .allowed:
            .current
        case .blocked:
            .error
        case .unknown:
            .unknown
        }
    }

    static func resolve(
        crawlers: [CrawlBarPermissionCrawler],
        statuses: [CrawlAppID: CrawlAppStatus])
        -> Self
    {
        let resolvedStatuses = crawlers.compactMap { statuses[$0.appID] }
        guard !resolvedStatuses.isEmpty else { return .unknown }
        if resolvedStatuses.contains(where: Self.statusLooksPermissionBlocked) {
            return .blocked
        }
        guard resolvedStatuses.count == crawlers.count else { return .unknown }
        return resolvedStatuses.allSatisfy { [.current, .stale].contains($0.state) } ? .allowed : .unknown
    }

    private static func statusLooksPermissionBlocked(_ status: CrawlAppStatus) -> Bool {
        guard status.state == .error else { return false }
        let text = ([status.summary] + status.errors + status.warnings)
            .joined(separator: "\n")
            .lowercased()
        return text.contains("operation not permitted")
            || text.contains("permission denied")
            || text.contains("not authorized")
            || text.contains("not permitted")
    }
}

private struct CrawlBarPermissionCrawler: Identifiable, Comparable {
    let appID: CrawlAppID
    let manifest: CrawlAppManifest

    var id: CrawlAppID { self.appID }

    var title: String {
        CrawlBarCrawlerTitle.text(for: self.appID, manifest: self.manifest)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private struct CrawlBarPermissionRow: View {
    let requirement: CrawlBarPermissionRequirement

    var body: some View {
        HStack(alignment: .center, spacing: CrawlBarSettingsLayout.panelContentSpacing) {
            Image(systemName: self.requirement.symbolName)
                .font(.system(size: CrawlBarSettingsLayout.rowIconFontSize))
                .foregroundStyle(.secondary)
                .frame(width: CrawlBarSettingsLayout.rowIconFrame, height: CrawlBarSettingsLayout.rowIconFrame)
            VStack(alignment: .leading, spacing: CrawlBarSettingsLayout.labelSpacing) {
                HStack(spacing: CrawlBarSettingsLayout.panelContentSpacing) {
                    Text(self.requirement.title)
                        .font(.callout.weight(.semibold))
                    CrawlBarStatusPill(
                        state: self.requirement.permissionState.appState,
                        label: self.requirement.permissionState.label)
                }
                CrawlBarPermissionCrawlerList(crawlers: self.requirement.crawlers)
            }
        }
        .padding(.vertical, CrawlBarSettingsLayout.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CrawlBarDraggableAppItem: View {
    let bundleURL: URL

    var body: some View {
        Label {
            Text("CrawlBar")
                .font(.callout.weight(.medium))
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: self.bundleURL.path))
                .resizable()
                .frame(
                    width: CrawlBarSettingsLayout.appIconRegular,
                    height: CrawlBarSettingsLayout.appIconRegular)
        }
        .padding(.horizontal, CrawlBarSettingsLayout.panelContentSpacing)
        .frame(maxWidth: .infinity, minHeight: CrawlBarSettingsLayout.dragItemHeight, alignment: .leading)
        .help("Drag CrawlBar into the Full Disk Access app list.")
        .onDrag {
            let provider = NSItemProvider(contentsOf: self.bundleURL) ?? NSItemProvider()
            provider.suggestedName = "CrawlBar.app"
            return provider
        }
    }
}

private struct CrawlBarPermissionCrawlerList: View {
    let crawlers: [CrawlBarPermissionCrawler]

    var body: some View {
        HStack(spacing: CrawlBarSettingsLayout.panelContentSpacing) {
            ForEach(self.crawlers) { crawler in
                CrawlBarPermissionCrawlerChip(crawler: crawler)
            }
        }
        .lineLimit(CrawlBarSettingsLayout.singleLineLimit)
    }
}

private struct CrawlBarPermissionCrawlerChip: View {
    let crawler: CrawlBarPermissionCrawler

    var body: some View {
        Label {
            Text(self.crawler.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(CrawlBarSettingsLayout.singleLineLimit)
                .truncationMode(.tail)
        } icon: {
            CrawlBarBrandIcon(manifest: self.crawler.manifest, appID: self.crawler.appID)
                .frame(
                    width: CrawlBarSettingsLayout.appIconSmall,
                    height: CrawlBarSettingsLayout.appIconSmall)
        }
    }
}
