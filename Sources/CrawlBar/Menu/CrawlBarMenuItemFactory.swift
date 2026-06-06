import AppKit
import SwiftUI

@MainActor
struct CrawlBarMenuItemFactory {
    func makeItem(
        for content: some View,
        enabled: Bool,
        highlightable: Bool = false,
        submenu: NSMenu? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = enabled
        if highlightable {
            let highlightState = CrawlBarMenuItemHighlightState()
            item.view = CrawlBarMenuItemHostingView(
                rootView: Self.highlightableRoot(content, highlightState: highlightState, showsSubmenuIndicator: submenu != nil),
                highlightState: highlightState)
        } else {
            item.view = CrawlBarMenuItemHostingView(rootView: Self.plainRoot(content))
        }
        item.submenu = submenu
        return item
    }

    func refreshViewHeights(in menu: NSMenu, width: CGFloat = CrawlBarMenuMetrics.width) {
        for item in menu.items {
            guard let view = item.view,
                  let measuring = view as? CrawlBarMenuItemMeasuring
            else { continue }
            let height = measuring.measuredHeight(width: width)
            if abs(view.frame.size.height - height) > 0.5 || view.frame.size.width != width {
                view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            }
        }
    }

    func clearHighlights(in menu: NSMenu) {
        for item in menu.items {
            (item.view as? CrawlBarMenuItemHighlighting)?.setHighlighted(false)
        }
    }

    private static func plainRoot(_ content: some View) -> AnyView {
        AnyView(
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading))
    }

    private static func highlightableRoot(
        _ content: some View,
        highlightState: CrawlBarMenuItemHighlightState,
        showsSubmenuIndicator: Bool)
        -> AnyView
    {
        AnyView(
            CrawlBarMenuItemContainerView(
                highlightState: highlightState,
                showsSubmenuIndicator: showsSubmenuIndicator)
            {
                content
            })
    }
}
