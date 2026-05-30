import AppKit
import SwiftUI

private enum CrawlBarMenuMetrics {
    static let width: CGFloat = 380
    static let proposedHeight: CGFloat = 720
    static let maxHeight: CGFloat = 360
    static let fallbackHeight: CGFloat = 28
    static let selectionHorizontalInset: CGFloat = 6
    static let selectionVerticalInset: CGFloat = 2
    static let selectionCornerRadius: CGFloat = 6
    static let submenuIndicatorTrailingPadding: CGFloat = 10
}

private struct CrawlBarMenuItemHighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var crawlBarMenuItemHighlighted: Bool {
        get { self[CrawlBarMenuItemHighlightedKey.self] }
        set { self[CrawlBarMenuItemHighlightedKey.self] = newValue }
    }
}

enum CrawlBarMenuHighlightStyle {
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)
    static let normalPrimaryText = Color(nsColor: .controlTextColor)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText.opacity(0.86) : self.normalSecondaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : Color(nsColor: .systemRed)
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}

@MainActor
protocol CrawlBarMenuItemMeasuring: AnyObject {
    func measuredHeight(width: CGFloat) -> CGFloat
}

@MainActor
protocol CrawlBarMenuItemHighlighting: AnyObject {
    func setHighlighted(_ highlighted: Bool)
}

@MainActor
final class CrawlBarMenuItemHighlightState: ObservableObject {
    @Published var isHighlighted = false
}

private struct CrawlBarMenuItemSelectionBackground: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(
            dx: CrawlBarMenuMetrics.selectionHorizontalInset,
            dy: CrawlBarMenuMetrics.selectionVerticalInset)
        return RoundedRectangle(
            cornerRadius: CrawlBarMenuMetrics.selectionCornerRadius,
            style: .continuous).path(in: inset)
    }
}

private struct CrawlBarMenuItemContainerView<Content: View>: View {
    @ObservedObject var highlightState: CrawlBarMenuItemHighlightState
    let showsSubmenuIndicator: Bool
    @ViewBuilder var content: Content

    var body: some View {
        self.content
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, self.showsSubmenuIndicator ? CrawlBarMenuMetrics.submenuIndicatorTrailingPadding : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.crawlBarMenuItemHighlighted, self.highlightState.isHighlighted)
            .foregroundStyle(CrawlBarMenuHighlightStyle.primary(self.highlightState.isHighlighted))
            .background(alignment: .topLeading) {
                if self.highlightState.isHighlighted {
                    CrawlBarMenuItemSelectionBackground()
                        .fill(CrawlBarMenuHighlightStyle.selectionBackground(true))
                }
            }
            .overlay(alignment: .topTrailing) {
                if self.showsSubmenuIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CrawlBarMenuHighlightStyle.secondary(self.highlightState.isHighlighted))
                        .padding(.top, 8)
                        .padding(.trailing, CrawlBarMenuMetrics.submenuIndicatorTrailingPadding)
                }
            }
    }
}

@MainActor
final class CrawlBarMenuItemHostingView: NSView, CrawlBarMenuItemMeasuring, CrawlBarMenuItemHighlighting {
    private let highlightState: CrawlBarMenuItemHighlightState?
    private let hostingController: NSHostingController<AnyView>
    private var contentVersion = 0
    private var cachedWidth: CGFloat?
    private var cachedHeight: CGFloat?
    private var cachedContentVersion = -1

    override var allowsVibrancy: Bool { true }

    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override var intrinsicContentSize: NSSize {
        let size = self.hostingController.view.intrinsicContentSize
        guard self.bounds.width > 0 else { return size }
        return NSSize(width: self.bounds.width, height: size.height)
    }

    init(rootView: AnyView, highlightState: CrawlBarMenuItemHighlightState? = nil) {
        self.highlightState = highlightState
        self.hostingController = NSHostingController(rootView: rootView)
        super.init(frame: .zero)
        self.contentVersion = 1
        self.configureHostingView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.hostingController.view.frame = self.bounds
    }

    func setHighlighted(_ highlighted: Bool) {
        self.highlightState?.isHighlighted = highlighted
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        if self.cachedWidth == width, self.cachedContentVersion == self.contentVersion, let cachedHeight {
            return cachedHeight
        }
        if self.frame.size.width != width || self.bounds.size.width != width {
            self.frame.size.width = width
            self.bounds.size.width = width
            self.hostingController.view.frame = self.bounds
            self.invalidateIntrinsicContentSize()
        }

        let proposed = NSSize(width: width, height: CrawlBarMenuMetrics.proposedHeight)
        let measured = self.hostingController.sizeThatFits(in: proposed)
        let safeHeight = self.safeMeasuredHeight(from: measured.height)
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let rounded = ceil(safeHeight * scale) / scale
        self.cachedWidth = width
        self.cachedHeight = rounded
        self.cachedContentVersion = self.contentVersion
        return rounded
    }

    func updateRootView(_ rootView: AnyView) {
        self.hostingController.rootView = rootView
        self.contentVersion += 1
        self.cachedWidth = nil
        self.cachedHeight = nil
        self.invalidateIntrinsicContentSize()
    }

    private func configureHostingView() {
        self.hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        self.hostingController.view.autoresizingMask = [.width, .height]
        self.hostingController.view.frame = self.bounds
        self.addSubview(self.hostingController.view)
        if #available(macOS 13.0, *) {
            self.hostingController.sizingOptions = [.minSize, .intrinsicContentSize]
        }
    }

    private func safeMeasuredHeight(from height: CGFloat) -> CGFloat {
        if height.isFinite, height > 0 {
            return min(height, CrawlBarMenuMetrics.maxHeight)
        }
        let intrinsic = self.hostingController.view.intrinsicContentSize.height
        if intrinsic.isFinite, intrinsic > 0 {
            return min(intrinsic, CrawlBarMenuMetrics.maxHeight)
        }
        return CrawlBarMenuMetrics.fallbackHeight
    }
}

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
