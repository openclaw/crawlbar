import AppKit
import CrawlBarCore

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
            NSColor(crawlBarHex: manifest?.branding.accentColor ?? "#6E6E73")
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

private extension NSColor {
    convenience init(crawlBarHex hex: String) {
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
