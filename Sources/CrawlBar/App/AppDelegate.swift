import AppKit
import CrawlBarCore

@MainActor
final class CrawlBarAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var refreshAnimationTimer: Timer?
    private var refreshAnimationFrame = 0
    private var pendingMenuReloadTask: Task<Void, Never>?
    private var isMenuOpen = false
    private var menuNeedsReloadAfterClose = false
    private let settingsWindowController = CrawlBarSettingsWindowController()
    private let menuBuilder = CrawlBarStatusMenuBuilder()
    private let model = CrawlBarMenuModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrawlBarLog.app.notice("CrawlBar launched")
        self.configureMainMenu()
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
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.hideFromApplicationSwitcher()
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "CrawlBar")

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(Self.showSettings(_:)),
            keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit CrawlBar",
            action: #selector(Self.quit(_:)),
            keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = mainMenu
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
        menu.delegate = self
        self.menuBuilder.rebuildMenu(
            menu,
            model: self.model,
            target: self,
            selectors: Self.menuActionSelectors,
            openSettings: { [weak self] appID in
                self?.openSettings(appID: appID)
            })
        self.statusItem?.menu = menu
        if let button = self.statusItem?.button {
            button.target = nil
            button.action = nil
            button.isEnabled = true
        }
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
        guard let button = self.statusItem?.button else { return }
        button.image = CrawlBarIconFactory.menuBarImage(rotationDegrees: rotation)
        button.toolTip = "CrawlBar"
        button.setAccessibilityLabel("CrawlBar")
        button.setAccessibilityTitle("CrawlBar")
        button.setAccessibilityHelp("Open CrawlBar")
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
        self.showInApplicationSwitcher()
        self.statusItem?.menu?.cancelTracking()
        Task { @MainActor [weak self] in
            // Let AppKit finish status-menu tracking before ordering the settings window.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            CrawlBarLog.app.debug("Opening settings")
            self.settingsWindowController.show(appID: appID)
        }
    }

    private func showInApplicationSwitcher() {
        // Settings needs regular activation so macOS treats the window like a normal app window for focus and accessibility.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.unhide(nil)
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
        self.menuBuilder.clearHighlights(in: menu)
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

    private static let menuActionSelectors = CrawlBarStatusMenuActionSelectors(
        showSettings: #selector(Self.showSettings(_:)),
        showSettingsForApp: #selector(Self.showSettingsForAppMenuItem(_:)),
        refreshAll: #selector(Self.refreshAll(_:)),
        openLogs: #selector(Self.openLogs(_:)),
        quit: #selector(Self.quit(_:)))
}
