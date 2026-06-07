import CrawlBarCore
import SwiftUI

extension CrawlBarAppDetailView {
    var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(CrawlBarCrawlerTitle.text(for: self.app.id, manifest: self.manifest))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    CrawlBarStatusPill(state: self.effectiveState)
                }
                Text(self.manifest?.description ?? self.app.id.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, alignment: .leading)
            Spacer()
            HStack(spacing: 6) {
                if !self.isComingSoon {
                    Button(action: self.refreshStatus) {
                        Image(systemName: self.isRefreshing ? "hourglass" : "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh status")
                }
            }
            .controlSize(.small)
        }
    }

    var comingSoonContent: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 44)
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 72, height: 72)
            Text("\(self.manifest?.displayName ?? "This crawler") has not shipped yet")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("CrawlBar will let you know when it is ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    var notInstalledContent: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 44)
            CrawlBarBrandIcon(manifest: self.manifest, appID: self.app.id)
                .frame(width: 72, height: 72)
            Text(self.notInstalledTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(self.notInstalledMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if self.manifest?.install != nil {
                Button {
                    self.installApp()
                } label: {
                    Label(self.installButtonTitle, systemImage: "square.and.arrow.down")
                }
                .disabled(self.runningAction != nil)
            }
            if self.runningAction == "install" {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    var isComingSoon: Bool {
        self.manifest?.availability == .comingSoon
    }

    var isMissingBinary: Bool {
        self.manifest?.availability == .available && self.installation?.binaryPath == nil
    }

    private var notInstalledTitle: String {
        if let sourceAppSuggestion,
           !self.sourceAppIsInstalled(sourceAppSuggestion)
        {
            return "No \(sourceAppSuggestion.name) app was found on this Mac"
        }
        return "\(CrawlBarCrawlerTitle.text(for: self.app.id, manifest: self.manifest)) is not installed"
    }

    private var notInstalledMessage: String {
        let binaryName = self.manifest?.binary.name ?? self.app.id.rawValue
        if let sourceAppSuggestion,
           !self.sourceAppIsInstalled(sourceAppSuggestion)
        {
            return "Install \(sourceAppSuggestion.name) first, then install \(binaryName) to enable sync, search, and status checks."
        }
        return "Install \(binaryName) to enable sync, search, and status checks."
    }

    private var sourceAppSuggestion: CrawlAppManifest.Suggestion? {
        guard let suggestion = self.manifest?.suggestion,
              suggestion.kind == .app
        else { return nil }
        return suggestion
    }

    private func sourceAppIsInstalled(_ suggestion: CrawlAppManifest.Suggestion) -> Bool {
        suggestion.bundleIDs.contains { bundleID in
            CrawlBarNativeAppLocator.url(for: bundleID) != nil
        }
    }
}
