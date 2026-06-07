import AppKit
import CrawlBarCore
import SwiftUI

extension CrawlBarAppDetailView {
    var syncSection: some View {
        CrawlBarDetailSection(title: "Sync") {
            self.syncSettings
            self.cloudArchiveSettings
            self.gitShareSettings
        }
    }

    var syncSettings: some View {
        CrawlBarPanel(title: "Sync") {
            VStack(alignment: .leading, spacing: 10) {
                CrawlBarSwitchRow(
                    title: "Enable crawler",
                    caption: "Allow CrawlBar to run actions and show live status.",
                    isOn: self.$app.enabled)
                    .onChange(of: self.app.enabled) { self.save() }
                CrawlBarSwitchRow(
                    title: "Show in menu bar",
                    caption: "Include this crawler in the menu bar status menu.",
                    isOn: self.$app.showInMenuBar)
                    .disabled(!self.app.enabled)
                    .onChange(of: self.app.showInMenuBar) { self.save() }
                CrawlBarSwitchRow(
                    title: "Run on schedule",
                    caption: "Refresh this crawler automatically in the background.",
                    isOn: self.$app.autoRefreshEnabled)
                    .disabled(!self.app.enabled)
                    .onChange(of: self.app.autoRefreshEnabled) { self.save() }
                CrawlBarSwitchRow(
                    title: "Use default schedule",
                    caption: "Follow the global interval from General settings.",
                    isOn: self.usesGlobalRefreshBinding)
                    .disabled(!self.app.enabled || !self.app.autoRefreshEnabled)
            }
            CrawlBarControlRow(
                title: "Custom schedule",
                caption: "Overrides the global interval for this crawler.")
            {
                Picker("Custom schedule", selection: self.refreshFrequencyBinding) {
                    ForEach(RefreshFrequency.allCases, id: \.self) { frequency in
                        Text(CrawlBarFrequencyLabel.text(for: frequency)).tag(frequency)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            .disabled(!self.app.enabled || !self.app.autoRefreshEnabled || self.app.refreshFrequency == nil)
            Text("Default schedule: \(CrawlBarFrequencyLabel.text(for: self.globalRefreshFrequency))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if self.installation?.binaryPath == nil, self.manifest?.install != nil {
                    Button {
                        self.installApp()
                    } label: {
                        Label(self.installButtonTitle, systemImage: "square.and.arrow.down")
                    }
                }
                if self.commandAvailable(self.app.preferredRefreshAction ?? "refresh") {
                    Button {
                        self.runAction(self.app.preferredRefreshAction ?? "refresh")
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                if self.commandAvailable("desktop-cache-import") {
                    Button {
                        self.runAction("desktop-cache-import")
                    } label: {
                        Label("Import Desktop", systemImage: "externaldrive.connected.to.line.below")
                    }
                }
                if self.commandAvailable("doctor") {
                    Button {
                        self.runAction("doctor")
                    } label: {
                        Label("Run Doctor", systemImage: "stethoscope")
                    }
                }
                if self.commandAvailable("unlock") {
                    Button {
                        self.runAction("unlock")
                    } label: {
                        Label("Unlock", systemImage: "key")
                    }
                }
                if self.nativeAppAvailable {
                    Button {
                        self.openNativeApp()
                    } label: {
                        Label("Open Source App", systemImage: "app")
                    }
                }
                if self.commandAvailable(self.app.preferredUpdateAction ?? "update") {
                    Button {
                        self.runAction(self.app.preferredUpdateAction ?? "update")
                    } label: {
                        Label("Update", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .disabled(self.runningAction != nil)
            if let runningAction {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running \(runningAction)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var gitShareSettings: some View {
        CrawlBarPanel(title: "Git Snapshot") {
            CrawlBarSwitchRow(
                title: "Manage snapshot",
                caption: "Keep a local Git export for this crawler's shareable data.",
                isOn: self.$app.shareEnabled)
                .onChange(of: self.app.shareEnabled) { self.save() }
            if self.hasSnapshotRemote {
                CrawlBarSwitchRow(
                    title: "Publish after sync",
                    caption: "Push the snapshot after a scheduled or manual sync.",
                    isOn: self.$app.shareAfterRefresh)
                    .disabled(!self.app.shareEnabled)
                    .onChange(of: self.app.shareAfterRefresh) { self.save() }
                HStack(spacing: 8) {
                    if self.commandAvailable(self.app.preferredShareAction ?? "publish") {
                        Button {
                            self.runAction(self.app.preferredShareAction ?? "publish")
                        } label: {
                            Label("Publish Snapshot", systemImage: "arrow.up.circle")
                        }
                    }
                    if self.commandAvailable(self.app.preferredUpdateAction ?? "update") {
                        Button {
                            self.runAction(self.app.preferredUpdateAction ?? "update")
                        } label: {
                            Label("Pull Updates", systemImage: "arrow.down.circle")
                        }
                    }
                }
                .disabled(!self.app.shareEnabled || self.runningAction != nil)
            }
            if self.hasSnapshotInfo {
                Divider()
                if let shareRepoPath = self.shareRepoPath {
                    CrawlBarFact(label: "Share Repo", value: shareRepoPath)
                }
                if let shareRemote = self.shareRemote {
                    CrawlBarFact(label: "Remote", value: shareRemote)
                }
                if let shareBranch = self.shareBranch {
                    CrawlBarFact(label: "Branch", value: shareBranch)
                }
            }
        }
    }

    @ViewBuilder
    var cloudArchiveSettings: some View {
        if self.commandAvailable("cloud-publish") || self.commandAvailable("remote-status") || self.commandAvailable("remote-archives") {
            CrawlBarPanel(title: "Cloudflare Archive") {
                CrawlBarOptionLabel(
                    title: "Remote SQLite archive",
                    caption: "Publish a compressed SQLite bundle and use the configured Worker archive for live reads.")
                HStack(spacing: 8) {
                    if self.commandAvailable("cloud-publish") {
                        Button {
                            self.runAction("cloud-publish")
                        } label: {
                            Label("Publish Cloud", systemImage: "icloud.and.arrow.up")
                        }
                    }
                    if self.commandAvailable("remote-status") {
                        Button {
                            self.runAction("remote-status")
                        } label: {
                            Label("Remote Status", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    if self.commandAvailable("remote-archives") {
                        Button {
                            self.runAction("remote-archives")
                        } label: {
                            Label("Archives", systemImage: "tray.full")
                        }
                    }
                }
                .disabled(self.runningAction != nil)
                if let remote = self.status?.remote {
                    Divider()
                    if let endpoint = remote.endpoint?.nilIfBlank {
                        CrawlBarFact(label: "Endpoint", value: endpoint)
                    }
                    if let archive = remote.archive?.nilIfBlank {
                        CrawlBarFact(label: "Archive", value: archive)
                    }
                    if let sqliteBundle = self.status?.sqliteBundle {
                        CrawlBarFact(label: "Bundle", value: self.bundleSummary(sqliteBundle))
                    }
                }
            }
        }
    }

    var hasSnapshotRemote: Bool {
        self.app.shareEnabled && self.shareRemote != nil
    }

    var hasSnapshotInfo: Bool {
        self.app.shareEnabled && (self.shareRepoPath != nil || self.shareRemote != nil || self.shareBranch != nil)
    }

    var shareRepoPath: String? {
        self.status?.share?.repoPath?.nilIfBlank ?? self.manifest?.paths.defaultShare?.nilIfBlank
    }

    var shareRemote: String? {
        self.status?.share?.remote?.nilIfBlank
    }

    var shareBranch: String? {
        self.status?.share?.branch?.nilIfBlank
    }

    var usesGlobalRefreshBinding: Binding<Bool> {
        Binding(
            get: { self.app.refreshFrequency == nil },
            set: {
                self.app.refreshFrequency = $0 ? nil : self.globalRefreshFrequency
                self.save()
            })
    }

    var refreshFrequencyBinding: Binding<RefreshFrequency> {
        Binding(
            get: { self.app.refreshFrequency ?? self.globalRefreshFrequency },
            set: {
                self.app.refreshFrequency = $0
                self.save()
            })
    }

    func commandAvailable(_ action: String) -> Bool {
        guard self.manifest?.availability == .available else { return false }
        return self.manifest?.commands[action] != nil && self.installation?.binaryPath != nil && self.app.enabled
    }

    var nativeAppAvailable: Bool {
        guard let bundleIdentifier = self.manifest?.branding.bundleIdentifier?.nilIfBlank else { return false }
        return CrawlBarNativeAppLocator.url(for: bundleIdentifier) != nil
    }

    func openNativeApp() {
        guard let bundleIdentifier = self.manifest?.branding.bundleIdentifier?.nilIfBlank,
              let url = CrawlBarNativeAppLocator.url(for: bundleIdentifier)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
