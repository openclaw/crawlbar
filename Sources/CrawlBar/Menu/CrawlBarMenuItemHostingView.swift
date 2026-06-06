import AppKit
import SwiftUI

@MainActor
protocol CrawlBarMenuItemMeasuring: AnyObject {
    func measuredHeight(width: CGFloat) -> CGFloat
}

@MainActor
protocol CrawlBarMenuItemHighlighting: AnyObject {
    func setHighlighted(_ highlighted: Bool)
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
