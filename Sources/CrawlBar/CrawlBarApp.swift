import AppKit
import CrawlBarCore
import SwiftUI

@main
@MainActor
enum CrawlBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = CrawlBarAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class CrawlBarAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menuItemFactory = CrawlBarMenuItemFactory()
    private var refreshTimer: Timer?
    private var refreshAnimationTimer: Timer?
    private var refreshAnimationFrame = 0
    private var pendingMenuReloadTask: Task<Void, Never>?
    private var isMenuOpen = false
    private var menuNeedsReloadAfterClose = false
    private let settingsWindowController = CrawlBarSettingsWindowController()
    private let model = CrawlBarMenuModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrawlBarLog.app.notice("CrawlBar launched")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(Self.statusesDidChange(_:)),
            name: .crawlBarStatusesDidChange,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(Self.configDidChange(_:)),
            name: .crawlBarConfigDidChange,
            object: nil)
        self.settingsWindowController.onClose = { [weak self] in
            self?.hideFromApplicationSwitcher()
        }
        if let appIcon = CrawlBarIconFactory.appIconImage() {
            NSApplication.shared.applicationIconImage = appIcon
        }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        self.statusItem = statusItem
        self.updateStatusButtonImage()
        self.reloadMenu()
        self.model.refreshAll { [weak self] in
            self?.scheduleMenuReload()
        }
        self.scheduleRefreshTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        CrawlBarLog.app.notice("CrawlBar terminated")
        self.pendingMenuReloadTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func reloadMenu() {
        self.pendingMenuReloadTask?.cancel()
        self.pendingMenuReloadTask = nil
        let startedAt = CFAbsoluteTimeGetCurrent()
        let menu = self.statusItem?.menu ?? NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.removeAllItems()

        menu.addItem(self.viewItem(for: CrawlBarMenuHeaderView(
            installations: self.model.visibleInstallations,
            statuses: self.model.statuses,
            isRefreshing: self.model.isRefreshing,
            refreshFrequency: self.model.refreshFrequency), enabled: false))
        menu.addItem(self.viewItem(for: CrawlBarMenuSeparatorRowView(), enabled: false))

        for (index, installation) in self.model.visibleInstallations.enumerated() {
            menu.addItem(self.appMenuItem(for: installation))
            if index < self.model.visibleInstallations.count - 1 {
                menu.addItem(self.viewItem(for: CrawlBarMenuSeparatorRowView(), enabled: false))
            }
        }

        menu.addItem(.separator())
        let refreshTitle = self.model.isRefreshing ? "Refreshing..." : "Refresh All"
        menu.addItem(self.actionItem(title: refreshTitle, action: #selector(Self.refreshAll(_:)), keyEquivalent: "r", systemImage: "arrow.clockwise"))
        menu.addItem(self.actionItem(title: "Open Logs", action: #selector(Self.openLogs(_:)), keyEquivalent: "l", systemImage: "folder"))
        menu.addItem(self.actionItem(title: "Settings...", action: #selector(Self.showSettings(_:)), keyEquivalent: ",", systemImage: "gearshape"))
        menu.addItem(.separator())
        menu.addItem(self.actionItem(title: "Quit CrawlBar", action: #selector(Self.quit(_:)), keyEquivalent: "q", systemImage: "power"))

        self.statusItem?.menu = menu
        if let button = self.statusItem?.button {
            button.target = nil
            button.action = nil
            button.isEnabled = true
        }
        self.menuItemFactory.refreshViewHeights(in: menu)
        self.syncRefreshAnimation()
        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        CrawlBarLog.app.debug("Reloaded menu in \(elapsedMilliseconds, privacy: .public)ms")
    }

    private func scheduleMenuReload() {
        guard !self.isMenuOpen else {
            self.menuNeedsReloadAfterClose = true
            return
        }
        self.pendingMenuReloadTask?.cancel()
        self.pendingMenuReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadMenu()
        }
    }

    private func appMenuItem(for installation: CrawlAppInstallation) -> NSMenuItem {
        let card = CrawlBarMenuCardView(
            installation: installation,
            status: self.model.statuses[installation.id],
            onOpen: { [weak self] in self?.openSettings(appID: installation.id) })
        let item = self.viewItem(for: card, enabled: true, highlightable: true)
        item.title = CrawlBarCrawlerTitle.text(for: installation.id, manifest: installation.manifest)
        item.representedObject = installation.id
        item.target = self
        item.action = #selector(Self.showSettingsForAppMenuItem(_:))
        return item
    }

    private func viewItem(for content: some View, enabled: Bool, highlightable: Bool = false) -> NSMenuItem {
        self.menuItemFactory.makeItem(for: content, enabled: enabled, highlightable: highlightable)
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String = "", systemImage: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        }
        return item
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

    private func scheduleRefreshTimer() {
        self.refreshTimer?.invalidate()
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.runDueAutoSync {
                    self?.scheduleMenuReload()
                }
            }
        }
    }

    private func syncRefreshAnimation() {
        self.updateStatusButtonImage()
        if self.model.isRefreshing {
            guard self.refreshAnimationTimer == nil else { return }
            self.refreshAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.advanceRefreshAnimation()
                }
            }
        } else {
            self.refreshAnimationTimer?.invalidate()
            self.refreshAnimationTimer = nil
            self.refreshAnimationFrame = 0
            self.updateStatusButtonImage()
        }
    }

    private func advanceRefreshAnimation() {
        guard self.model.isRefreshing else {
            self.syncRefreshAnimation()
            return
        }
        self.refreshAnimationFrame = (self.refreshAnimationFrame + 1) % 8
        self.updateStatusButtonImage()
    }

    private func updateStatusButtonImage() {
        let rotation = self.model.isRefreshing ? CGFloat(self.refreshAnimationFrame) * 45 : 0
        self.statusItem?.button?.image = CrawlBarIconFactory.menuBarImage(rotationDegrees: rotation)
        self.statusItem?.button?.toolTip = nil
    }

    @objc private func refreshAll(_ sender: Any?) {
        self.model.refreshAll { [weak self] in
            self?.scheduleMenuReload()
        }
        self.reloadMenu()
    }

    @objc private func showSettings(_ sender: Any?) {
        self.openSettings(appID: nil)
    }

    @objc private func showSettingsForAppMenuItem(_ sender: NSMenuItem) {
        self.openSettings(appID: sender.representedObject as? CrawlAppID)
    }

    private func openSettings(appID: CrawlAppID?) {
        self.statusItem?.menu?.cancelTracking()
        CrawlBarLog.app.debug("Opening settings")
        self.showInApplicationSwitcher()
        self.settingsWindowController.show(appID: appID)
    }

    private func showInApplicationSwitcher() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func hideFromApplicationSwitcher() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    @objc private func openLogs(_ sender: Any?) {
        self.statusItem?.menu?.cancelTracking()
        CrawlBarLog.app.debug("Opening action logs folder")
        NSWorkspace.shared.open(CrawlActionLogStore.defaultDirectory())
    }

    @objc private func quit(_ sender: Any?) {
        self.statusItem?.menu?.cancelTracking()
        CrawlBarLog.app.notice("Quit requested")
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        self.isMenuOpen = true
        if self.pendingMenuReloadTask != nil {
            self.reloadMenu()
            self.isMenuOpen = true
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        self.isMenuOpen = false
        self.menuItemFactory.clearHighlights(in: menu)
        if self.menuNeedsReloadAfterClose {
            self.menuNeedsReloadAfterClose = false
            self.reloadMenu()
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            guard let view = menuItem.view as? CrawlBarMenuItemHighlighting else { continue }
            view.setHighlighted(menuItem == item && menuItem.isEnabled)
        }
    }

    @objc private func statusesDidChange(_ notification: Notification) {
        self.scheduleMenuReload()
    }

    @objc private func configDidChange(_ notification: Notification) {
        self.model.reloadInstallations()
        self.scheduleRefreshTimer()
        self.reloadMenu()
    }
}

private struct CrawlActionStatusUpdate: Sendable {
    let status: CrawlAppStatus
    let actionFailure: CrawlAppStatus?
}

@MainActor
final class CrawlBarMenuModel: NSObject {
    private let registry = CrawlAppRegistry()
    private let runner: CrawlCommandRunner
    private let statusService: CrawlStatusService
    private let logStore = CrawlActionLogStore()

    var installations: [CrawlAppInstallation] = []
    var statuses: [CrawlAppID: CrawlAppStatus] = [:]
    var isRefreshing = false
    var refreshFrequency: RefreshFrequency = .fifteenMinutes
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var appConfigs: [CrawlAppID: CrawlBarAppConfig] = [:]
    private var lastAutoSyncByAppID: [CrawlAppID: Date] = [:]

    override init() {
        let runner = CrawlCommandRunner()
        self.runner = runner
        self.statusService = CrawlStatusService(runner: runner)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(Self.statusesDidChange(_:)),
            name: .crawlBarStatusesDidChange,
            object: nil)
        self.reloadInstallations()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var visibleInstallations: [CrawlAppInstallation] {
        self.installations.filter { installation in
            guard installation.manifest.availability == .available else { return false }
            return self.appConfigs[installation.id]?.showInMenuBar ?? true
        }
    }

    func appConfig(for id: CrawlAppID) -> CrawlBarAppConfig? {
        self.appConfigs[id]
    }

    func reloadInstallations() {
        if let config = try? self.registry.loadConfig() {
            self.refreshFrequency = config.refreshFrequency
            self.appConfigs = Dictionary(uniqueKeysWithValues: config.apps.map { ($0.id, $0) })
        } else {
            CrawlBarLog.config.error("Failed to load CrawlBar config")
        }
        self.installations = (try? self.registry.installations(includeDisabled: true)) ?? []
    }

    func refreshAll(onComplete: @escaping @MainActor () -> Void) {
        self.refreshTask?.cancel()
        let generation = UUID()
        self.refreshGeneration = generation
        self.isRefreshing = true
        let registry = self.registry
        let statusService = self.statusService
        self.refreshTask = Task.detached {
            let installations = (try? registry.installationsForStatus(includeDisabled: true)) ?? []
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                self.installations = installations
                onComplete()
            }
            let partitioned = Self.partitionStatuses(installations: installations, statusService: statusService)
            if !partitioned.immediate.isEmpty {
                await MainActor.run {
                    guard self.refreshGeneration == generation else { return }
                    for status in partitioned.immediate {
                        self.statuses[status.appID] = status
                    }
                    CrawlBarStateBroadcast.statusesDidChange(Dictionary(uniqueKeysWithValues: partitioned.immediate.map { ($0.appID, $0) }))
                    onComplete()
                }
            }
            await withTaskGroup(of: CrawlAppStatus.self) { group in
                for installation in partitioned.commandInstallations {
                    group.addTask {
                        guard !Task.isCancelled else {
                            return CrawlAppStatus(appID: installation.id, state: .unknown, summary: "Refresh cancelled")
                        }
                        return statusService.status(for: installation, timeoutSeconds: 5)
                    }
                }
                for await status in group {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        guard self.refreshGeneration == generation else { return }
                        self.statuses[status.appID] = status
                        CrawlBarStateBroadcast.statusesDidChange([status.appID: status])
                        onComplete()
                    }
                }
            }
            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                self.isRefreshing = false
                self.refreshTask = nil
                onComplete()
            }
        }
    }

    nonisolated private static func partitionStatuses(
        installations: [CrawlAppInstallation],
        statusService: CrawlStatusService)
        -> (immediate: [CrawlAppStatus], commandInstallations: [CrawlAppInstallation])
    {
        var immediate: [CrawlAppStatus] = []
        var commandInstallations: [CrawlAppInstallation] = []
        for installation in installations {
            if let status = statusService.immediateStatus(for: installation) {
                immediate.append(status)
            } else {
                commandInstallations.append(installation)
            }
        }
        return (immediate, commandInstallations)
    }

    func runDueAutoSync(onComplete: @escaping @MainActor () -> Void) {
        guard !self.isRefreshing else { return }
        self.reloadInstallations()
        let now = Date()
        let dueInstallations = self.installations.filter { installation in
            guard let config = self.appConfigs[installation.id], config.enabled, config.autoRefreshEnabled else { return false }
            guard installation.enabled, installation.binaryPath != nil else { return false }
            guard let seconds = (config.refreshFrequency ?? self.refreshFrequency).seconds else { return false }
            let last = self.lastAutoSyncByAppID[installation.id] ?? .distantPast
            return now.timeIntervalSince(last) >= seconds
        }
        guard !dueInstallations.isEmpty else { return }

        self.isRefreshing = true
        let configs = self.appConfigs
        let registry = self.registry
        let runner = self.runner
        let statusService = self.statusService
        let logStore = self.logStore
        Task.detached {
            let updates = dueInstallations.map { installation -> CrawlActionStatusUpdate in
                let actionInstallation = (try? registry.installation(for: installation.id, includeSecrets: true)) ?? installation
                let statusInstallation = (try? registry.installationForStatus(for: installation.id)) ?? installation

                func failureUpdate(_ failure: CrawlAppStatus) -> CrawlActionStatusUpdate {
                    CrawlActionStatusUpdate(
                        status: statusService.status(for: statusInstallation, timeoutSeconds: 5),
                        actionFailure: failure)
                }

                if let config = configs[installation.id] {
                    let refreshAction = config.preferredRefreshAction ?? "refresh"
                    do {
                        CrawlBarLog.actions.notice("Running scheduled \(refreshAction, privacy: .public) for \(installation.id.rawValue, privacy: .public)")
                        let result = try runner.run(installation: actionInstallation, action: refreshAction, timeoutSeconds: 600)
                        _ = try? logStore.save(result)
                        if !result.succeeded {
                            CrawlBarLog.actions.error(
                                "Scheduled \(refreshAction, privacy: .public) for \(installation.id.rawValue, privacy: .public) failed with exit \(result.exitCode)")
                            return failureUpdate(Self.actionFailureStatus(result))
                        }
                    } catch {
                        CrawlBarLog.actions.error(
                            "Scheduled \(refreshAction, privacy: .public) for \(installation.id.rawValue, privacy: .public) threw: \(error.localizedDescription, privacy: .public)")
                        return failureUpdate(Self.actionFailureStatus(
                            appID: installation.id,
                            action: refreshAction,
                            message: error.localizedDescription))
                    }
                    if config.shareEnabled, config.shareAfterRefresh {
                        let shareAction = config.preferredShareAction ?? "publish"
                        do {
                            CrawlBarLog.actions.notice("Running scheduled \(shareAction, privacy: .public) for \(installation.id.rawValue, privacy: .public)")
                            let result = try runner.run(installation: actionInstallation, action: shareAction, timeoutSeconds: 600)
                            _ = try? logStore.save(result)
                            if !result.succeeded {
                                CrawlBarLog.actions.error(
                                    "Scheduled \(shareAction, privacy: .public) for \(installation.id.rawValue, privacy: .public) failed with exit \(result.exitCode)")
                                return failureUpdate(Self.actionFailureStatus(result))
                            }
                        } catch {
                            CrawlBarLog.actions.error(
                                "Scheduled \(shareAction, privacy: .public) for \(installation.id.rawValue, privacy: .public) threw: \(error.localizedDescription, privacy: .public)")
                            return failureUpdate(Self.actionFailureStatus(
                                appID: installation.id,
                                action: shareAction,
                                message: error.localizedDescription))
                        }
                    }
                }
                return CrawlActionStatusUpdate(
                    status: statusService.status(for: statusInstallation, timeoutSeconds: 5),
                    actionFailure: nil)
            }
            await MainActor.run {
                var changedStatuses: [CrawlAppID: CrawlAppStatus] = [:]
                for update in updates {
                    let status = update.actionFailure.map {
                        Self.actionFailureStatus($0, refreshedStatus: update.status, currentStatus: self.statuses[$0.appID])
                    } ?? update.status
                    self.statuses[status.appID] = status
                    changedStatuses[status.appID] = status
                    if update.actionFailure == nil, status.state != .error {
                        self.lastAutoSyncByAppID[status.appID] = now
                    }
                }
                CrawlBarStateBroadcast.statusesDidChange(changedStatuses)
                self.isRefreshing = false
                onComplete()
            }
        }
    }

    private func mergeStatuses(_ incoming: [CrawlAppID: CrawlAppStatus]) {
        for (appID, status) in incoming {
            self.statuses[appID] = status
        }
    }

    @objc private func statusesDidChange(_ notification: Notification) {
        guard let statuses = CrawlBarStateBroadcast.statuses(from: notification) else { return }
        self.mergeStatuses(statuses)
    }

    nonisolated private static func actionFailureStatus(_ result: CrawlCommandResult) -> CrawlAppStatus {
        let fallback = "\(result.action) failed with exit \(result.exitCode)"
        return CrawlAppStatus.commandFailure(
            appID: result.appID,
            action: result.action,
            message: result.stderr.nilIfBlank ?? result.stdout.nilIfBlank,
            fallback: fallback)
    }

    nonisolated private static func actionFailureStatus(appID: CrawlAppID, action: String, message: String) -> CrawlAppStatus {
        CrawlAppStatus.commandFailure(
            appID: appID,
            action: action,
            message: message,
            fallback: "\(action) failed")
    }

    nonisolated private static func actionFailureStatus(
        _ failure: CrawlAppStatus,
        refreshedStatus: CrawlAppStatus?,
        currentStatus: CrawlAppStatus?)
        -> CrawlAppStatus
    {
        guard let metadataStatus = CrawlAppStatus.richestMetadataStatus(refreshedStatus, fallback: currentStatus) else {
            return failure
        }
        return metadataStatus.mergingActionFailure(failure)
    }

}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}
