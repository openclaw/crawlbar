import Foundation

package extension CrawlAppManifest {
    enum InstallMethod: String, Codable, Equatable, Sendable {
        case homebrew
    }

    struct Install: Codable, Equatable, Sendable {
        package var method: InstallMethod
        package var package: String

        package init(method: InstallMethod, package: String) {
            self.method = method
            self.package = package
        }
    }

    enum SuggestionKind: String, Codable, Equatable, Sendable {
        case always
        case app
    }

    struct Suggestion: Codable, Equatable, Sendable {
        package var kind: SuggestionKind
        package var name: String
        package var bundleIDs: [String]

        package init(kind: SuggestionKind, name: String, bundleIDs: [String] = []) {
            self.kind = kind
            self.name = name
            self.bundleIDs = bundleIDs
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case name
            case bundleIDs = "bundle_ids"
        }
    }
}
