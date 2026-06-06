import AppKit
import CrawlBarCore
import SwiftUI

@MainActor
struct CrawlBarStatusMenuActionSelectors {
    let showSettings: Selector
    let showSettingsForApp: Selector
    let refreshAll: Selector
    let openLogs: Selector
    let quit: Selector
}

@MainActor
struct CrawlBarStatusMenuBuilder {
    private let itemFactory = CrawlBarMenuItemFactory()

    func rebuildMenu(
        _ menu: NSMenu,
        model: CrawlBarMenuModel,
        target: AnyObject,
        selectors: CrawlBarStatusMenuActionSelectors,
        openSettings: @escaping (CrawlAppID?) -> Void)
    {
        let visibleInstallations = model.visibleInstallations

        menu.autoenablesItems = false
        menu.removeAllItems()

        menu.addItem(self.viewItem(for: CrawlBarMenuHeaderView(
            installations: visibleInstallations,
            statuses: model.statuses,
            isRefreshing: model.isRefreshing,
            refreshFrequency: model.refreshFrequency), enabled: false))

        self.addCrawlers(
            visibleInstallations,
            statuses: model.statuses,
            to: menu,
            target: target,
            selector: selectors.showSettingsForApp,
            openSettings: openSettings)

        menu.addItem(.separator())
        let refreshTitle = model.isRefreshing ? "Refreshing..." : "Refresh All"
        let refreshItem = self.actionItem(
            title: refreshTitle,
            action: selectors.refreshAll,
            target: target,
            keyEquivalent: "r",
            systemImage: "arrow.clockwise")
        refreshItem.isEnabled = !model.statusTargetInstallations.isEmpty
        menu.addItem(refreshItem)
        menu.addItem(self.actionItem(
            title: "Open Logs",
            action: selectors.openLogs,
            target: target,
            keyEquivalent: "l",
            systemImage: "folder"))
        menu.addItem(self.actionItem(
            title: "Settings...",
            action: selectors.showSettings,
            target: target,
            keyEquivalent: ",",
            systemImage: "gearshape"))
        menu.addItem(.separator())
        menu.addItem(self.actionItem(
            title: "Quit CrawlBar",
            action: selectors.quit,
            target: target,
            keyEquivalent: "q",
            systemImage: "power"))

        self.itemFactory.refreshViewHeights(in: menu)
    }

    func clearHighlights(in menu: NSMenu) {
        self.itemFactory.clearHighlights(in: menu)
    }

    private func addCrawlers(
        _ installations: [CrawlAppInstallation],
        statuses: [CrawlAppID: CrawlAppStatus],
        to menu: NSMenu,
        target: AnyObject,
        selector: Selector,
        openSettings: @escaping (CrawlAppID?) -> Void)
    {
        guard !installations.isEmpty else { return }
        menu.addItem(self.viewItem(for: CrawlBarMenuSeparatorRowView(), enabled: false))
        for (index, installation) in installations.enumerated() {
            menu.addItem(self.appMenuItem(
                for: installation,
                status: statuses[installation.id],
                target: target,
                selector: selector,
                openSettings: openSettings))
            if index < installations.count - 1 {
                menu.addItem(self.viewItem(for: CrawlBarMenuSeparatorRowView(), enabled: false))
            }
        }
    }

    private func appMenuItem(
        for installation: CrawlAppInstallation,
        status: CrawlAppStatus?,
        target: AnyObject,
        selector: Selector,
        openSettings: @escaping (CrawlAppID?) -> Void)
        -> NSMenuItem
    {
        let card = CrawlBarMenuCardView(
            installation: installation,
            status: status,
            onOpen: { openSettings(installation.id) })
        return self.crawlerItem(
            for: card,
            installation: installation,
            target: target,
            selector: selector)
    }

    private func crawlerItem(
        for content: some View,
        installation: CrawlAppInstallation,
        target: AnyObject,
        selector: Selector)
        -> NSMenuItem
    {
        let item = self.viewItem(for: content, enabled: true, highlightable: true)
        item.title = CrawlBarCrawlerTitle.text(for: installation.id, manifest: installation.manifest)
        item.representedObject = installation.id
        item.target = target
        item.action = selector
        return item
    }

    private func viewItem(for content: some View, enabled: Bool, highlightable: Bool = false) -> NSMenuItem {
        self.itemFactory.makeItem(for: content, enabled: enabled, highlightable: highlightable)
    }

    private func actionItem(
        title: String,
        action: Selector,
        target: AnyObject,
        keyEquivalent: String = "",
        systemImage: String? = nil)
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        }
        return item
    }
}
