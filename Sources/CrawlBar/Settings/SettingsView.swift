import CrawlBarCore
import SwiftUI

struct CrawlBarSettingsView: View {
    @ObservedObject var model: CrawlBarSettingsModel
    @State private var isSidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if self.isSidebarVisible {
                self.sidebar
                    .frame(width: CrawlBarSettingsLayout.sidebarWidth)
            }
            self.detailContainer
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    self.isSidebarVisible.toggle()
                } label: {
                    Label(self.sidebarToggleTitle, systemImage: "sidebar.left")
                }
                .help(self.sidebarToggleTitle)
            }
        }
        .frame(
            minWidth: CrawlBarSettingsLayout.minWindowWidth,
            maxWidth: .infinity,
            minHeight: CrawlBarSettingsLayout.minWindowHeight,
            maxHeight: .infinity,
            alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebar: some View {
        List {
            Section("CrawlBar") {
                Button {
                    self.model.selectedSidebarItem = .general
                } label: {
                    CrawlBarGeneralSidebarRow(isSelected: self.model.selectedSidebarItem == .general)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .listRowBackground(CrawlBarSidebarSelectionBackground(isSelected: self.model.selectedSidebarItem == .general))
                .accessibilityAddTraits(self.model.selectedSidebarItem == .general ? .isSelected : [])
            }
            ForEach(self.model.crawlerSections) { section in
                Section {
                    ForEach(section.apps) { app in
                        let item = CrawlBarSettingsSidebarItem.crawler(app.id)
                        Button {
                            self.model.selectedSidebarItem = item
                        } label: {
                            CrawlBarSidebarRow(
                                app: app,
                                section: section.kind,
                                manifest: self.model.installations[app.id]?.manifest,
                                status: self.model.statuses[app.id],
                                binaryPath: self.model.installations[app.id]?.binaryPath,
                                isSelected: self.model.selectedSidebarItem == item)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .listRowBackground(CrawlBarSidebarSelectionBackground(isSelected: self.model.selectedSidebarItem == item))
                        .accessibilityAddTraits(self.model.selectedSidebarItem == item ? .isSelected : [])
                    }
                } header: {
                    CrawlBarSidebarSectionHeader(title: section.kind.title)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var sidebarToggleTitle: String {
        self.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
    }

    @ViewBuilder
    private var detailContainer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = self.model.lastError {
                CrawlBarIssueBanner(message: error, state: .error)
                    .padding(.horizontal, CrawlBarSettingsLayout.detailHorizontalPadding)
                    .padding(.top, CrawlBarSettingsLayout.detailVerticalPadding)
                    .padding(.bottom, 12)
            }
            self.selectedDetail
                .disabled(self.model.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if self.model.isLoading && self.model.apps.isEmpty {
            ProgressView("Loading settings...")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            switch self.model.selectedSidebarItem {
            case .general:
                CrawlBarGeneralSettingsView(model: self.model)
            case .crawler(let selectedID):
                if self.model.apps.contains(where: { $0.id == selectedID })
                {
                    CrawlBarAppDetailView(
                        app: self.binding(for: selectedID),
                        globalRefreshFrequency: self.model.refreshFrequency,
                        installation: self.model.installations[selectedID],
                        status: self.model.statuses[selectedID],
                        latestResult: self.model.recentResults[selectedID],
                        isRefreshing: self.model.isRefreshing,
                        runningAction: self.model.runningActions[selectedID],
                        actionMessage: self.model.actionMessages[selectedID],
                        refreshStatus: { self.model.refreshAll() },
                        runAction: { action in self.model.runAction(action, appID: selectedID) },
                        installApp: { self.model.installApp(selectedID) },
                        backupDatabases: { self.model.backupDatabases(selectedID) },
                        openDataFolder: { self.model.openDataFolder(selectedID) },
                        configValueChanged: { option, value in self.model.configValueDidChange(appID: selectedID, option: option, value: value) },
                        save: { self.model.save() },
                        saveDebounced: { self.model.saveDebounced() })
                        .padding(.horizontal, CrawlBarSettingsLayout.detailHorizontalPadding)
                        .padding(.vertical, CrawlBarSettingsLayout.detailVerticalPadding)
                } else {
                    ContentUnavailableView(
                        "No crawler selected",
                        systemImage: "sidebar.left")
                }
            case nil:
                ContentUnavailableView(
                    "No crawler selected",
                    systemImage: "sidebar.left")
            }
        }
    }

    private func binding(for id: CrawlAppID) -> Binding<CrawlBarAppConfig> {
        Binding(
            get: {
                self.model.apps.first(where: { $0.id == id }) ?? CrawlBarAppConfig(id: id)
            },
            set: {
                guard let index = self.model.apps.firstIndex(where: { $0.id == id }) else { return }
                self.model.apps[index] = $0
            })
    }
}
