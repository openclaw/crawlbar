import SwiftUI

extension CrawlBarAppDetailView {
    var statusSection: some View {
        CrawlBarDetailSection(title: "Status") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 260), spacing: 14, alignment: .top),
                    GridItem(.flexible(minimum: 260), spacing: 14, alignment: .top),
                ],
                alignment: .leading,
                spacing: 14)
            {
                self.statusSummary
                self.sourceSummary
                self.latestRunSummary
            }
        }
    }

    var statusSummary: some View {
        CrawlBarPanel(title: "Status") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    CrawlBarFact(label: "Current", value: self.status?.summary ?? self.statusFallback)
                    CrawlBarFact(label: "Last Sync", value: self.lastSyncSummary)
                }
                GridRow {
                    CrawlBarFact(
                        label: "Databases",
                        value: self.databaseSummary)
                    CrawlBarFact(label: "Binary", value: self.binarySummary)
                }
            }
            if let issue = self.primaryIssue {
                CrawlBarIssueBanner(message: issue, state: self.issueState)
            }
        }
    }

    var sourceSummary: some View {
        CrawlBarPanel(title: "Sources") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    CrawlBarFact(label: "Refresh", value: self.refreshSourceSummary)
                    CrawlBarFact(label: "Archive", value: self.archiveSourceSummary)
                }
                GridRow {
                    CrawlBarFact(label: "Snapshot", value: self.snapshotSummary)
                    CrawlBarFact(label: "Config", value: self.configSourceSummary)
                }
            }
        }
    }

    var latestRunSummary: some View {
        CrawlBarPanel(title: "Latest Run") {
            if let latestResult {
                HStack(spacing: 8) {
                    CrawlBarStatusDot(state: latestResult.succeeded ? .current : .error)
                    Text(Self.actionTitle(latestResult.action))
                        .font(.callout.weight(.medium))
                    Text(latestResult.succeeded ? "finished" : "failed")
                        .font(.callout)
                        .foregroundStyle(latestResult.succeeded ? Color.secondary : Color.red)
                    Spacer(minLength: 8)
                    Text(CrawlBarDateText.relative(latestResult.finishedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if latestResult.shouldShowExitCode {
                    CrawlBarFact(label: "Exit", value: "\(latestResult.exitCode)")
                }
                if let output = latestResult.userFacingRunMessage {
                    Text(output)
                        .font(.caption)
                        .foregroundStyle(latestResult.succeeded ? Color.secondary : Color.red)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            } else {
                Text("No action logs yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
