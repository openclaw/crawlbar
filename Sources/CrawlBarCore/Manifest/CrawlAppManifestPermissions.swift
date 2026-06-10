import Foundation

public extension CrawlAppManifest {
    struct Permission: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var optional: Bool

        public init(
            id: String,
            label: String,
            optional: Bool = false)
        {
            self.id = id
            self.label = label
            self.optional = optional
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case label
            case optional
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.label = try container.decode(String.self, forKey: .label)
            self.optional = try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false
        }
    }
}
