import Foundation

package extension CrawlAppManifest {
    struct Branding: Codable, Equatable, Sendable {
        package var symbolName: String
        package var accentColor: String
        package var iconPath: String?
        package var bundleIdentifier: String?

        package init(
            symbolName: String,
            accentColor: String,
            iconPath: String? = nil,
            bundleIdentifier: String? = nil)
        {
            self.symbolName = symbolName
            self.accentColor = accentColor
            self.iconPath = iconPath
            self.bundleIdentifier = bundleIdentifier
        }

        private enum CodingKeys: String, CodingKey {
            case symbolName = "symbol_name"
            case accentColor = "accent_color"
            case iconPath = "icon_path"
            case bundleIdentifier = "bundle_identifier"
        }
    }
}
