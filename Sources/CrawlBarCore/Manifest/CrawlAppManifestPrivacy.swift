import Foundation

public extension CrawlAppManifest {
    struct Privacy: Codable, Equatable, Sendable {
        public var containsPrivateMessages: Bool
        public var exportsSecrets: Bool
        public var localOnlyScopes: [String]

        public init(
            containsPrivateMessages: Bool = false,
            exportsSecrets: Bool = false,
            localOnlyScopes: [String] = [])
        {
            self.containsPrivateMessages = containsPrivateMessages
            self.exportsSecrets = exportsSecrets
            self.localOnlyScopes = localOnlyScopes
        }

        private enum CodingKeys: String, CodingKey {
            case containsPrivateMessages = "contains_private_messages"
            case exportsSecrets = "exports_secrets"
            case localOnlyScopes = "local_only_scopes"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.containsPrivateMessages = try container.decodeIfPresent(Bool.self, forKey: .containsPrivateMessages) ?? false
            self.exportsSecrets = try container.decodeIfPresent(Bool.self, forKey: .exportsSecrets) ?? false
            self.localOnlyScopes = try container.decodeIfPresent([String].self, forKey: .localOnlyScopes) ?? []
        }
    }
}
