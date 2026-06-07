import Foundation

public extension CrawlAppManifest {
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
