import AppKit
import CrawlBarCore
import SwiftUI

struct CrawlBarGeneralSettingsView: View {
    @ObservedObject var model: CrawlBarSettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CrawlBar")
                            .font(.title3.weight(.semibold))
                        Text("Menu bar control plane for local crawler apps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        self.model.refreshAll()
                    } label: {
                        Label("Refresh All", systemImage: "arrow.clockwise")
                    }
                    .disabled(self.model.isRefreshing)
                }

                CrawlBarPanel(title: "App") {
                    HStack(spacing: 8) {
                        Button {
                            self.model.installCLI()
                        } label: {
                            Label("Install CLI", systemImage: "terminal")
                        }
                        .disabled(self.model.isInstallingCLI)
                        Button {
                            self.model.openConfigFile()
                        } label: {
                            Label("Open Config", systemImage: "doc.text")
                        }
                        Button {
                            self.model.openLogsFolder()
                        } label: {
                            Label("Open Logs", systemImage: "folder")
                        }
                    }
                    .controlSize(.small)
                    CrawlBarFact(label: "CLI install path", value: "~/.local/bin/crawlbar")
                    CrawlBarFact(label: "Config", value: CrawlBarConfigStore().fileURL.path)
                    if let message = self.model.appActionMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                CrawlBarPanel(title: "Scheduling") {
                    CrawlBarControlRow(
                        title: "Default schedule",
                        caption: "Used by crawlers that inherit the global sync interval.")
                    {
                        Picker("Default schedule", selection: self.$model.refreshFrequency) {
                            ForEach(RefreshFrequency.allCases, id: \.self) { frequency in
                                Text(CrawlBarFrequencyLabel.text(for: frequency)).tag(frequency)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .onChange(of: self.model.refreshFrequency) {
                            self.model.save()
                        }
                    }
                }

                CrawlBarPanel(title: "Discovery") {
                    ForEach(self.model.manifestDirectories, id: \.self) { directory in
                        CrawlBarFact(label: "Manifest Directory", value: directory)
                    }
                    if !self.model.manifestDiagnostics.isEmpty {
                        Divider()
                        ForEach(self.model.manifestDiagnostics) { diagnostic in
                            Label {
                                Text("\(diagnostic.path): \(diagnostic.message)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }

                CrawlBarPanel(title: "Crawler Inventory") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            CrawlBarFact(label: "Ready", value: "\(self.readyCount)")
                            CrawlBarFact(label: "Missing CLI", value: "\(self.missingCount)")
                            CrawlBarFact(label: "Coming Soon", value: "\(self.comingSoonCount)")
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.bottom, CrawlBarSettingsLayout.detailBottomPadding)
        }
        .padding(.horizontal, CrawlBarSettingsLayout.detailHorizontalPadding)
        .padding(.vertical, CrawlBarSettingsLayout.detailVerticalPadding)
    }

    private var readyCount: Int {
        self.model.installations.values.filter { $0.manifest.availability == .available && $0.binaryPath != nil }.count
    }

    private var missingCount: Int {
        self.model.installations.values.filter { $0.manifest.availability == .available && $0.binaryPath == nil }.count
    }

    private var comingSoonCount: Int {
        self.model.installations.values.filter { $0.manifest.availability == .comingSoon }.count
    }
}
