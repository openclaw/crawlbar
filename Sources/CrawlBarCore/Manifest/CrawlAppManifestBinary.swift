import Foundation

package extension CrawlAppManifest {
    enum Availability: String, Codable, Equatable, Sendable {
        case available
        case comingSoon = "coming_soon"
    }

    struct Binary: Codable, Equatable, Sendable {
        package var name: String
        package var minVersion: String?

        package init(name: String, minVersion: String? = nil) {
            self.name = name
            self.minVersion = minVersion
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case minVersion = "min_version"
        }
    }
}
