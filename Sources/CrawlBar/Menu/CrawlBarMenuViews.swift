import AppKit
import CrawlBarCore
import SwiftUI

private enum CrawlBarMenuStyle {
    static let cardHorizontalPadding: CGFloat = 13
    static let cardVerticalPadding: CGFloat = 7
    static let cardSpacing: CGFloat = 6
    static let separatorInset: CGFloat = 13
    static let separatorVerticalPadding: CGFloat = 4
    static let headerHorizontalPadding: CGFloat = 13
    static let headerTopPadding: CGFloat = 10
    static let headerBottomPadding: CGFloat = 7
}

struct CrawlBarMenuHeaderView: View {
    let installations: [CrawlAppInstallation]
    let statuses: [CrawlAppID: CrawlAppStatus]
    let isRefreshing: Bool
    let refreshFrequency: RefreshFrequency

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("CrawlBar")
                        .font(.subheadline.weight(.semibold))
                    Text(self.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(self.installations.prefix(9), id: \.id) { installation in
                    CrawlBarBrandIcon(manifest: installation.manifest, appID: installation.id)
                        .frame(width: 20, height: 20)
                        .help(CrawlBarCrawlerTitle.text(for: installation.id, manifest: installation.manifest))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, CrawlBarMenuStyle.headerHorizontalPadding)
        .padding(.top, CrawlBarMenuStyle.headerTopPadding)
        .padding(.bottom, CrawlBarMenuStyle.headerBottomPadding)
    }

    private var summary: String {
        if self.isRefreshing {
            return "Refreshing crawler status"
        }
        let current = self.installations.filter {
            self.effectiveState(for: $0, status: self.statuses[$0.id]) == .current
        }.count
        return "\(current) current · \(CrawlBarFrequencyLabel.text(for: self.refreshFrequency))"
    }

    private func effectiveState(for installation: CrawlAppInstallation, status: CrawlAppStatus?) -> CrawlAppState {
        if installation.manifest.availability == .comingSoon { return .disabled }
        if !installation.enabled { return .disabled }
        if installation.binaryPath == nil { return .needsConfig }
        let state = status?.state ?? .unknown
        if status?.isRecoverableGraincrawlSourceFailure == true {
            return .stale
        }
        return state
    }
}

struct CrawlBarMenuCardView: View {
    let installation: CrawlAppInstallation
    let status: CrawlAppStatus?
    let onOpen: () -> Void
    @Environment(\.crawlBarMenuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                CrawlBarBrandIcon(manifest: self.installation.manifest, appID: self.installation.id)
                    .frame(width: 30, height: 30)
                CrawlBarStatusDot(state: self.effectiveState)
                    .padding(2)
                    .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: CrawlBarMenuStyle.cardSpacing) {
                self.header
                self.detail
                self.metrics
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CrawlBarMenuStyle.cardHorizontalPadding)
        .padding(.vertical, CrawlBarMenuStyle.cardVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: self.onOpen)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(CrawlBarCrawlerTitle.text(for: self.installation.id, manifest: self.installation.manifest))
                .font(.subheadline)
                .fontWeight(.regular)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(CrawlBarStatusLabel.text(for: self.effectiveState))
                .font(.system(size: 10))
                .foregroundStyle(self.statusColor)
                .lineLimit(1)
        }
    }

    private var detail: some View {
        Text(self.detailText)
            .font(.caption)
            .foregroundStyle(CrawlBarMenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(2)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var metrics: some View {
        let metrics = self.metricParts
        if !metrics.isEmpty {
            HStack(spacing: 10) {
                ForEach(metrics, id: \.self) { metric in
                    Text(metric)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(CrawlBarMenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var effectiveState: CrawlAppState {
        if self.installation.manifest.availability == .comingSoon { return .disabled }
        if !self.installation.enabled { return .disabled }
        if self.installation.binaryPath == nil { return .needsConfig }
        let state = self.status?.state ?? .unknown
        if self.status?.isRecoverableGraincrawlSourceFailure == true {
            return .stale
        }
        return state
    }

    private var detailText: String {
        if self.installation.binaryPath == nil {
            return "Missing \(self.installation.manifest.binary.name)"
        }
        if let summary = self.status?.summary.nilIfBlank {
            return summary
        }
        return self.installation.manifest.description
    }

    private var metricParts: [String] {
        guard let status else { return [] }
        var parts = status.counts.prefix(2).map {
            "\($0.label) \(Self.countFormatter.string(from: NSNumber(value: $0.value)) ?? "\($0.value)")"
        }
        if let syncedAt = status.lastSyncAt ?? status.databases.first(where: { $0.isPrimary })?.modifiedAt {
            parts.append(CrawlBarDateText.relative(syncedAt))
        }
        return parts
    }

    private var statusColor: Color {
        if self.isHighlighted { return CrawlBarMenuHighlightStyle.selectionText }
        switch self.effectiveState {
        case .current:
            return Color(nsColor: .systemGreen)
        case .stale, .unknown:
            return Color(nsColor: .systemOrange)
        case .syncing:
            return Color(nsColor: .systemBlue)
        case .needsConfig, .needsAuth, .error:
            return Color(nsColor: .systemRed)
        case .disabled:
            return CrawlBarMenuHighlightStyle.secondary(false)
        }
    }

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

struct CrawlBarMenuSeparatorRowView: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.leading, CrawlBarMenuStyle.separatorInset)
            .padding(.vertical, CrawlBarMenuStyle.separatorVerticalPadding)
    }
}
