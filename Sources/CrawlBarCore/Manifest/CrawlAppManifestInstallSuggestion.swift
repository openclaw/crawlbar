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

package extension CrawlAppManifest {
    func withSuggestion(_ suggestion: Suggestion) -> Self {
        var manifest = self
        manifest.suggestion = suggestion
        return manifest
    }

    enum SuggestionKind: Equatable, Sendable {
        case always
        case app
    }

    struct Suggestion: Equatable, Sendable {
        package var kind: SuggestionKind
        package var name: String
        package var bundleIDs: [String]

        package init(kind: SuggestionKind, name: String, bundleIDs: [String] = []) {
            self.kind = kind
            self.name = name
            self.bundleIDs = bundleIDs
        }
    }
}
