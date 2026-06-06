import Foundation

public extension CrawlAppManifest {
    enum Availability: String, Codable, Equatable, Sendable {
        case available
        case comingSoon = "coming_soon"
    }

    struct Binary: Codable, Equatable, Sendable {
        public var name: String
        public var minVersion: String?

        public init(name: String, minVersion: String? = nil) {
            self.name = name
            self.minVersion = minVersion
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case minVersion = "min_version"
        }
    }
}
