import AppKit
import CrawlBarCore
import SwiftUI

enum CrawlBarBrandPalette {
    static func accent(for appID: CrawlAppID, manifest: CrawlAppManifest?) -> NSColor {
        switch appID.rawValue {
        case "gitcrawl":
            NSColor(calibratedWhite: 0.08, alpha: 1)
        case "slacrawl":
            NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.32, alpha: 1)
        case "discrawl":
            NSColor(calibratedRed: 0.35, green: 0.40, blue: 0.95, alpha: 1)
        case "telecrawl":
            NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.85, alpha: 1)
        case "notcrawl":
            NSColor(calibratedWhite: 0.08, alpha: 1)
        case "gogcli":
            NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1)
        case "wacli":
            NSColor(calibratedRed: 0.15, green: 0.83, blue: 0.40, alpha: 1)
        case "birdclaw":
            NSColor(calibratedWhite: 0.02, alpha: 1)
        case "graincrawl":
            NSColor(calibratedRed: 0.83, green: 0.63, blue: 0.09, alpha: 1)
        default:
            NSColor(hex: manifest?.branding.accentColor ?? "#6E6E73")
        }
    }
}

enum CrawlBarCrawlerTitle {
    static func text(for appID: CrawlAppID, manifest: CrawlAppManifest?) -> String {
        let source = manifest?.displayName.nilIfBlank ?? appID.rawValue
        guard let binary = manifest?.binary.name.nilIfBlank, binary != source else {
            return source
        }
        return "\(source) (\(binary))"
    }
}

@MainActor
enum CrawlBarNativeAppLocator {
    private static var urlsByBundleIdentifier: [String: URL] = [:]

    static func url(for bundleIdentifier: String) -> URL? {
        if let cached = Self.urlsByBundleIdentifier[bundleIdentifier] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        Self.urlsByBundleIdentifier[bundleIdentifier] = url
        return url
    }
}

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

    private static func cacheSizeKey(for size: CGFloat) -> Int {
        Int((size * 2).rounded())
    }

    private static func statusColor(for state: CrawlAppState) -> NSColor {
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

    private static func brandedImage(for appID: CrawlAppID, manifest: CrawlAppManifest?, size: CGFloat) -> NSImage? {
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

    private static func bundledIcon(for appID: CrawlAppID) -> NSImage? {
        guard let name = Self.bundledIconName(for: appID),
              let url = Self.bundledIconURL(named: name)
        else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func bundledIconURL(named name: String) -> URL? {
        for bundle in Self.resourceBundleCandidates() {
            if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "BrandIcons")
                ?? bundle.url(forResource: name, withExtension: "png")
            {
                return url
            }
        }
        return nil
    }

    private static func resourceBundleCandidates() -> [Bundle] {
        let resourceBundleName = "CrawlBar_CrawlBar.bundle"
        let candidateURLs = [
            // SwiftPM executable bundles currently look beside the .app root.
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName),
            // Conventional app bundles keep resources under Contents/Resources.
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            // During local development, the executable and resource bundle share a build directory.
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

    private static func bundledIconName(for appID: CrawlAppID) -> String? {
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

    private static func sizedImage(_ source: NSImage, size: CGFloat) -> NSImage {
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

    private static func drawTile(appID: CrawlAppID, manifest: CrawlAppManifest?, rect: NSRect) {
        let radius = rect.width * 0.22
        let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        switch appID.rawValue {
        case "gogcli":
            NSColor.white.setFill()
            tile.fill()
            NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
            tile.lineWidth = max(1, rect.width * 0.035)
            tile.stroke()
            Self.drawGoogleGlyph(in: rect)
        case "notcrawl":
            NSColor.white.setFill()
            tile.fill()
            NSColor(calibratedWhite: 0.12, alpha: 1).setStroke()
            tile.lineWidth = max(1, rect.width * 0.035)
            tile.stroke()
            Self.drawNotionN(in: rect)
        case "wacli":
            NSColor(calibratedRed: 0.15, green: 0.83, blue: 0.40, alpha: 1).setFill()
            tile.fill()
            Self.drawWhatsAppGlyph(in: rect)
        case "birdclaw":
            NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
            tile.fill()
            Self.drawXGlyph(in: rect)
        case "graincrawl":
            NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.80, alpha: 1).setFill()
            tile.fill()
            NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.18, alpha: 0.25).setStroke()
            tile.lineWidth = max(1, rect.width * 0.035)
            tile.stroke()
            Self.drawGranolaGlyph(in: rect)
        case "telecrawl":
            NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.85, alpha: 1).setFill()
            tile.fill()
            Self.drawTelegramGlyph(in: rect)
        default:
            let accent = CrawlBarBrandPalette.accent(for: appID, manifest: manifest)
            accent.withAlphaComponent(0.16).setFill()
            tile.fill()
            accent.withAlphaComponent(0.32).setStroke()
            tile.lineWidth = max(1, rect.width * 0.035)
            tile.stroke()
            switch appID.rawValue {
            case "gitcrawl":
                Self.drawGitGlyph(in: rect, color: accent)
            case "slacrawl":
                Self.drawSlackGlyph(in: rect)
            case "discrawl":
                Self.drawDiscordGlyph(in: rect, color: accent)
            default:
                Self.drawTerminalGlyph(in: rect, color: accent)
            }
        }
    }

    private static func drawTelegramGlyph(in rect: NSRect) {
        NSColor.white.setFill()
        let plane = NSBezierPath()
        plane.move(to: NSPoint(x: rect.minX + rect.width * 0.18, y: rect.midY + rect.height * 0.03))
        plane.line(to: NSPoint(x: rect.maxX - rect.width * 0.16, y: rect.maxY - rect.height * 0.22))
        plane.line(to: NSPoint(x: rect.maxX - rect.width * 0.32, y: rect.minY + rect.height * 0.20))
        plane.line(to: NSPoint(x: rect.midX + rect.width * 0.02, y: rect.midY - rect.height * 0.04))
        plane.line(to: NSPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.31))
        plane.close()
        plane.fill()

        NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.85, alpha: 1).withAlphaComponent(0.9).setStroke()
        let fold = NSBezierPath()
        fold.lineWidth = max(1, rect.width * 0.035)
        fold.lineCapStyle = .round
        fold.move(to: NSPoint(x: rect.midX + rect.width * 0.02, y: rect.midY - rect.height * 0.04))
        fold.line(to: NSPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.22))
        fold.stroke()
    }

    private static func drawGoogleGlyph(in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.27
        let width = max(2.4, rect.width * 0.105)
        let arcs: [(NSColor, CGFloat, CGFloat)] = [
            (NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1), -38, 42),
            (NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.18, alpha: 1), -145, -38),
            (NSColor(calibratedRed: 0.20, green: 0.66, blue: 0.33, alpha: 1), -218, -145),
            (NSColor(calibratedRed: 0.92, green: 0.26, blue: 0.21, alpha: 1), 42, 142),
        ]
        for (color, start, end) in arcs {
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .butt
            path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end)
            path.stroke()
        }
        NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1).setStroke()
        let crossbar = NSBezierPath()
        crossbar.lineWidth = width
        crossbar.lineCapStyle = .butt
        crossbar.move(to: NSPoint(x: rect.midX, y: rect.midY))
        crossbar.line(to: NSPoint(x: rect.maxX - rect.width * 0.18, y: rect.midY))
        crossbar.stroke()
    }

    private static func drawWhatsAppGlyph(in rect: NSRect) {
        NSColor.white.setFill()
        let bubbleRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
        let bubble = NSBezierPath(ovalIn: bubbleRect)
        bubble.fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.23))
        tail.line(to: NSPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.12))
        tail.line(to: NSPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.18))
        tail.close()
        tail.fill()

        NSColor(calibratedRed: 0.15, green: 0.83, blue: 0.40, alpha: 1).setStroke()
        let phone = NSBezierPath()
        phone.lineWidth = max(1.9, rect.width * 0.07)
        phone.lineCapStyle = .round
        phone.move(to: NSPoint(x: rect.minX + rect.width * 0.37, y: rect.midY + rect.height * 0.12))
        phone.curve(
            to: NSPoint(x: rect.maxX - rect.width * 0.34, y: rect.midY - rect.height * 0.13),
            controlPoint1: NSPoint(x: rect.midX - rect.width * 0.02, y: rect.midY - rect.height * 0.03),
            controlPoint2: NSPoint(x: rect.midX + rect.width * 0.07, y: rect.midY - rect.height * 0.11))
        phone.stroke()
    }

    private static func drawXGlyph(in rect: NSRect) {
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = max(2.2, rect.width * 0.095)
        path.lineCapStyle = .butt
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.29, y: rect.maxY - rect.height * 0.24))
        path.line(to: NSPoint(x: rect.maxX - rect.width * 0.25, y: rect.minY + rect.height * 0.24))
        path.move(to: NSPoint(x: rect.maxX - rect.width * 0.28, y: rect.maxY - rect.height * 0.24))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.24))
        path.stroke()
    }

    private static func drawGranolaGlyph(in rect: NSRect) {
        let color = NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.18, alpha: 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSString(string: "G").draw(
            in: rect.offsetBy(dx: 0, dy: -rect.height * 0.07),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: rect.width * 0.58, weight: .bold),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ])
        color.withAlphaComponent(0.7).setStroke()
        let baseY = rect.minY + rect.height * 0.24
        for index in 0..<4 {
            let x = rect.minX + rect.width * (0.30 + CGFloat(index) * 0.11)
            let line = NSBezierPath()
            line.lineWidth = max(1.2, rect.width * 0.035)
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: x, y: baseY))
            line.line(to: NSPoint(x: x, y: baseY + rect.height * (index.isMultiple(of: 2) ? 0.08 : 0.14)))
            line.stroke()
        }
    }

    private static func drawNotionN(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let fontSize = rect.width * 0.64
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        NSString(string: "N").draw(
            in: rect.offsetBy(dx: 0, dy: -rect.height * 0.06),
            withAttributes: attributes)
    }

    private static func drawGitGlyph(in rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let left = NSPoint(x: rect.minX + rect.width * 0.28, y: rect.midY)
        let top = NSPoint(x: rect.maxX - rect.width * 0.27, y: rect.maxY - rect.height * 0.28)
        let bottom = NSPoint(x: rect.maxX - rect.width * 0.27, y: rect.minY + rect.height * 0.28)
        let path = NSBezierPath()
        path.lineWidth = max(2, rect.width * 0.08)
        path.lineCapStyle = .round
        path.move(to: left)
        path.line(to: center)
        path.line(to: top)
        path.move(to: center)
        path.line(to: bottom)
        path.stroke()
        for point in [left, center, top, bottom] {
            NSBezierPath(ovalIn: NSRect(
                x: point.x - rect.width * 0.085,
                y: point.y - rect.width * 0.085,
                width: rect.width * 0.17,
                height: rect.width * 0.17)).fill()
        }
    }

    private static func drawSlackGlyph(in rect: NSRect) {
        let colors = [
            NSColor(calibratedRed: 0.20, green: 0.73, blue: 0.61, alpha: 1),
            NSColor(calibratedRed: 0.22, green: 0.53, blue: 0.92, alpha: 1),
            NSColor(calibratedRed: 0.91, green: 0.18, blue: 0.39, alpha: 1),
            NSColor(calibratedRed: 0.94, green: 0.72, blue: 0.18, alpha: 1),
        ]
        let w = rect.width * 0.16
        let h = rect.height * 0.43
        let r = w * 0.5
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let shapes = [
            (NSRect(x: center.x - w * 1.15, y: center.y - h * 0.12, width: w, height: h), CGFloat(0)),
            (NSRect(x: center.x + w * 0.15, y: center.y - h * 0.88, width: h, height: w), CGFloat(0)),
            (NSRect(x: center.x + w * 0.15, y: center.y - h * 0.12, width: w, height: h), CGFloat(0)),
            (NSRect(x: center.x - h * 0.88, y: center.y + w * 0.15, width: h, height: w), CGFloat(0)),
        ]
        for index in shapes.indices {
            colors[index].setFill()
            NSBezierPath(
                roundedRect: shapes[index].0,
                xRadius: r,
                yRadius: r).fill()
        }
    }

    private static func drawDiscordGlyph(in rect: NSRect, color: NSColor) {
        color.setFill()
        let body = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.28), xRadius: rect.width * 0.16, yRadius: rect.width * 0.16)
        body.fill()
        NSColor.white.withAlphaComponent(0.95).setFill()
        for x in [rect.midX - rect.width * 0.11, rect.midX + rect.width * 0.11] {
            NSBezierPath(ovalIn: NSRect(
                x: x - rect.width * 0.035,
                y: rect.midY - rect.height * 0.025,
                width: rect.width * 0.07,
                height: rect.width * 0.07)).fill()
        }
        let smile = NSBezierPath()
        smile.lineWidth = max(1.3, rect.width * 0.035)
        smile.move(to: NSPoint(x: rect.midX - rect.width * 0.1, y: rect.midY - rect.height * 0.13))
        smile.curve(
            to: NSPoint(x: rect.midX + rect.width * 0.1, y: rect.midY - rect.height * 0.13),
            controlPoint1: NSPoint(x: rect.midX - rect.width * 0.04, y: rect.midY - rect.height * 0.19),
            controlPoint2: NSPoint(x: rect.midX + rect.width * 0.04, y: rect.midY - rect.height * 0.19))
        smile.stroke()
    }

    private static func drawTerminalGlyph(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = max(1.8, rect.width * 0.06)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.28, y: rect.midY + rect.height * 0.14))
        path.line(to: NSPoint(x: rect.midX - rect.width * 0.02, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.28, y: rect.midY - rect.height * 0.14))
        path.move(to: NSPoint(x: rect.midX + rect.width * 0.08, y: rect.midY - rect.height * 0.16))
        path.line(to: NSPoint(x: rect.maxX - rect.width * 0.24, y: rect.midY - rect.height * 0.16))
        path.stroke()
    }
}

struct CrawlBarBrandIcon: View {
    let manifest: CrawlAppManifest?
    let appID: CrawlAppID

    var body: some View {
        Image(nsImage: CrawlBarIconFactory.image(
            for: self.appID,
            manifest: self.manifest,
            size: 64))
        .resizable()
        .interpolation(.high)
        .aspectRatio(1, contentMode: .fit)
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: trimmed)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        self.init(
            calibratedRed: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            alpha: 1)
    }
}
