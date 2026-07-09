import Foundation

public extension CrawlAppManifest {
    struct Branding: Codable, Equatable, Sendable {
        public var symbolName: String
        public var accentColor: String
        public var iconPath: String?
        public var bundleIdentifier: String?

        public init(
            symbolName: String = "",
            accentColor: String = "#6E6E73",
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

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? ""
            self.accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor) ?? "#6E6E73"
            self.iconPath = try container.decodeIfPresent(String.self, forKey: .iconPath)
            self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        }
    }
}
