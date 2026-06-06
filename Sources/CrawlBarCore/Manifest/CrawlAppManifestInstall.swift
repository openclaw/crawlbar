import Foundation

public extension CrawlAppManifest {
    enum InstallMethod: String, Codable, Equatable, Sendable {
        case homebrew
    }

    struct Install: Codable, Equatable, Sendable {
        public var method: InstallMethod
        public var package: String

        public init(method: InstallMethod, package: String) {
            self.method = method
            self.package = package
        }
    }
}
