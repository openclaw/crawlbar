import Foundation

public extension CrawlAppManifest {
    enum ConfigOptionKind: String, Codable, Equatable, Sendable {
        case string
        case secret
        case boolean
        case number
        case choice
    }

    struct ConfigOption: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var kind: ConfigOptionKind
        public var help: String?
        public var placeholder: String?
        public var defaultValue: String?
        public var choices: [String]
        public var envVar: String?
        public var configKey: String?

        public init(
            id: String,
            label: String,
            kind: ConfigOptionKind = .string,
            help: String? = nil,
            placeholder: String? = nil,
            defaultValue: String? = nil,
            choices: [String] = [],
            envVar: String? = nil,
            configKey: String? = nil)
        {
            self.id = id
            self.label = label
            self.kind = kind
            self.help = help
            self.placeholder = placeholder
            self.defaultValue = defaultValue
            self.choices = choices
            self.envVar = envVar
            self.configKey = configKey
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case label
            case kind
            case help
            case placeholder
            case defaultValue = "default_value"
            case choices
            case envVar = "env_var"
            case configKey = "config_key"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? self.id
            self.kind = try container.decodeIfPresent(ConfigOptionKind.self, forKey: .kind) ?? .string
            self.help = try container.decodeIfPresent(String.self, forKey: .help)
            self.placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
            self.defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            self.choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
            self.envVar = try container.decodeIfPresent(String.self, forKey: .envVar)
            self.configKey = try container.decodeIfPresent(String.self, forKey: .configKey)
        }
    }

    struct ConfigSection: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var caption: String?
        public var optionIDs: [String]

        public init(id: String, title: String, caption: String? = nil, optionIDs: [String]) {
            self.id = id
            self.title = title
            self.caption = caption
            self.optionIDs = optionIDs
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case caption
            case optionIDs = "option_ids"
        }
    }
}
