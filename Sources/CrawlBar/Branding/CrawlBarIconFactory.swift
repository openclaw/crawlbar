import AppKit
import CrawlBarCore

@MainActor
enum CrawlBarIconFactory {
    private static var imageCache: [String: NSImage] = [:]
    private static var menuBarImageCache: [String: NSImage] = [:]
    private static var statusDotImageCache: [String: NSImage] = [:]

    static func image(for appID: CrawlAppID, manifest: CrawlAppManifest?, size: CGFloat = 32) -> NSImage {
        let cacheKey = [
            "app",
            appID.rawValue,
            "\(Self.cacheSizeKey(for: size))",
            manifest?.branding.iconPath?.nilIfBlank ?? "",
            manifest?.branding.bundleIdentifier?.nilIfBlank ?? "",
            manifest?.branding.accentColor.nilIfBlank ?? "",
        ].joined(separator: "|")
        if let cached = Self.imageCache[cacheKey] {
            return cached
        }
        if let image = Self.brandedImage(for: appID, manifest: manifest, size: size) {
            Self.imageCache[cacheKey] = image
            return image
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        Self.drawTile(appID: appID, manifest: manifest, rect: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        image.isTemplate = false
        Self.imageCache[cacheKey] = image
        return image
    }

    static func menuBarImage(size: CGFloat = 18, rotationDegrees: CGFloat = 0) -> NSImage {
        let cacheKey = "\(Self.cacheSizeKey(for: size))|\(Int(rotationDegrees.rounded()))"
        if let cached = Self.menuBarImageCache[cacheKey] {
            return cached
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        if rotationDegrees != 0 {
            let transform = NSAffineTransform()
            transform.translateX(by: size / 2, yBy: size / 2)
            transform.rotate(byDegrees: rotationDegrees)
            transform.translateX(by: -size / 2, yBy: -size / 2)
            transform.concat()
        }
        let stroke = NSColor.labelColor
        stroke.setStroke()
        let line = NSBezierPath()
        line.lineWidth = max(1.6, size * 0.1)
        let inset = size * 0.19
        line.move(to: NSPoint(x: inset, y: size * 0.68))
        line.curve(
            to: NSPoint(x: size - inset, y: size * 0.68),
            controlPoint1: NSPoint(x: size * 0.38, y: size * 0.94),
            controlPoint2: NSPoint(x: size * 0.62, y: size * 0.94))
        line.move(to: NSPoint(x: inset, y: size * 0.32))
        line.curve(
            to: NSPoint(x: size - inset, y: size * 0.32),
            controlPoint1: NSPoint(x: size * 0.38, y: size * 0.06),
            controlPoint2: NSPoint(x: size * 0.62, y: size * 0.06))
        line.stroke()

        for point in [
            NSPoint(x: inset, y: size * 0.68),
            NSPoint(x: size - inset, y: size * 0.68),
            NSPoint(x: inset, y: size * 0.32),
            NSPoint(x: size - inset, y: size * 0.32),
        ] {
            let dot = NSBezierPath(ovalIn: NSRect(
                x: point.x - size * 0.105,
                y: point.y - size * 0.105,
                width: size * 0.21,
                height: size * 0.21))
            stroke.setFill()
            dot.fill()
        }
        image.unlockFocus()
        image.isTemplate = true
        Self.menuBarImageCache[cacheKey] = image
        return image
    }

    static func statusDotImage(for state: CrawlAppState, size: CGFloat = 12) -> NSImage {
        let cacheKey = "\(state.rawValue)|\(Self.cacheSizeKey(for: size))"
        if let cached = Self.statusDotImageCache[cacheKey] {
            return cached
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let rect = NSRect(x: 2, y: 2, width: size - 4, height: size - 4)
        let dot = NSBezierPath(ovalIn: rect)
        Self.statusColor(for: state).setFill()
        dot.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        dot.lineWidth = 0.75
        dot.stroke()
        image.unlockFocus()
        image.isTemplate = false
        Self.statusDotImageCache[cacheKey] = image
        return image
    }

    static func appIconImage() -> NSImage? {
        for bundle in Self.resourceBundleCandidates() {
            if let url = bundle.url(forResource: "AppIcon", withExtension: "png") {
                return NSImage(contentsOf: url)
            }
        }
        return nil
    }

    static func cacheSizeKey(for size: CGFloat) -> Int {
        Int((size * 2).rounded())
    }

    static func statusColor(for state: CrawlAppState) -> NSColor {
        switch state {
        case .current:
            NSColor.systemGreen
        case .stale, .syncing, .unknown:
            NSColor.systemYellow
        case .needsConfig, .needsAuth, .error:
            NSColor.systemRed
        case .disabled:
            NSColor.systemGray
        }
    }

    static func brandedImage(for appID: CrawlAppID, manifest: CrawlAppManifest?, size: CGFloat) -> NSImage? {
        if let iconPath = manifest?.branding.iconPath?.nilIfBlank {
            let expandedPath = NSString(string: iconPath).expandingTildeInPath
            if let image = NSImage(contentsOfFile: expandedPath) {
                return Self.sizedImage(image, size: size)
            }
        }
        if let bundleIdentifier = manifest?.branding.bundleIdentifier?.nilIfBlank,
           let appURL = CrawlBarNativeAppLocator.url(for: bundleIdentifier)
        {
            return Self.sizedImage(NSWorkspace.shared.icon(forFile: appURL.path), size: size)
        }
        if let image = Self.bundledIcon(for: appID) {
            return Self.sizedImage(image, size: size)
        }
        return nil
    }

    static func bundledIcon(for appID: CrawlAppID) -> NSImage? {
        guard let name = Self.bundledIconName(for: appID),
              let url = Self.bundledIconURL(named: name)
        else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    static func bundledIconURL(named name: String) -> URL? {
        for bundle in Self.resourceBundleCandidates() {
            if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "BrandIcons")
                ?? bundle.url(forResource: name, withExtension: "png")
            {
                return url
            }
        }
        return nil
    }

    static func resourceBundleCandidates() -> [Bundle] {
        let resourceBundleName = "CrawlBar_CrawlBar.bundle"
        let candidateURLs = [
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName),
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(resourceBundleName),
        ].compactMap { $0 }

        var seen = Set<String>()
        var bundles: [Bundle] = []
        for url in candidateURLs where seen.insert(url.path).inserted {
            if let bundle = Bundle(url: url) {
                bundles.append(bundle)
            }
        }
        bundles.append(Bundle.main)
        return bundles
    }

    static func bundledIconName(for appID: CrawlAppID) -> String? {
        switch appID.rawValue {
        case "gitcrawl":
            "gitcrawl"
        case "slacrawl":
            "slacrawl"
        case "discrawl":
            "discrawl"
        case "notcrawl":
            "notcrawl"
        case "gogcli":
            "google"
        case "wacli":
            "wacli"
        case "birdclaw":
            "x"
        case "graincrawl":
            "graincrawl"
        default:
            nil
        }
    }

    static func sizedImage(_ source: NSImage, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        source.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
