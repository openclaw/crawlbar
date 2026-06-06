import Foundation

public struct CrawlBarAppConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: CrawlAppID
    public var enabled: Bool
    public var binaryPath: String?
    public var configPath: String?
    public var refreshFrequency: RefreshFrequency?
    public var preferredRefreshAction: String?
    public var autoRefreshEnabled: Bool
    public var shareEnabled: Bool
    public var shareAfterRefresh: Bool
    public var preferredShareAction: String?
    public var preferredUpdateAction: String?
    public var showInMenuBar: Bool
    public var configValues: [String: String]

    public init(
        id: CrawlAppID,
        enabled: Bool = true,
        binaryPath: String? = nil,
        configPath: String? = nil,
        refreshFrequency: RefreshFrequency? = nil,
        preferredRefreshAction: String? = "refresh",
        autoRefreshEnabled: Bool = false,
        shareEnabled: Bool = false,
        shareAfterRefresh: Bool = false,
        preferredShareAction: String? = "publish",
        preferredUpdateAction: String? = "update",
        showInMenuBar: Bool = true,
        configValues: [String: String] = [:])
    {
        self.id = id
        self.enabled = enabled
        self.binaryPath = binaryPath
        self.configPath = configPath
        self.refreshFrequency = refreshFrequency
        self.preferredRefreshAction = preferredRefreshAction
        self.autoRefreshEnabled = autoRefreshEnabled
        self.shareEnabled = shareEnabled
        self.shareAfterRefresh = shareAfterRefresh
        self.preferredShareAction = preferredShareAction
        self.preferredUpdateAction = preferredUpdateAction
        self.showInMenuBar = showInMenuBar
        self.configValues = configValues
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case binaryPath = "binary_path"
        case configPath = "config_path"
        case refreshFrequency = "refresh_frequency"
        case preferredRefreshAction = "preferred_refresh_action"
        case autoRefreshEnabled = "auto_refresh_enabled"
        case shareEnabled = "share_enabled"
        case shareAfterRefresh = "share_after_refresh"
        case preferredShareAction = "preferred_share_action"
        case preferredUpdateAction = "preferred_update_action"
        case showInMenuBar = "show_in_menu_bar"
        case configValues = "config_values"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(CrawlAppID.self, forKey: .id)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.binaryPath = try container.decodeIfPresent(String.self, forKey: .binaryPath)
        self.configPath = try container.decodeIfPresent(String.self, forKey: .configPath)
        self.refreshFrequency = try container.decodeIfPresent(RefreshFrequency.self, forKey: .refreshFrequency)
        self.preferredRefreshAction = try container.decodeIfPresent(String.self, forKey: .preferredRefreshAction) ?? "refresh"
        self.autoRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRefreshEnabled) ?? false
        self.shareEnabled = try container.decodeIfPresent(Bool.self, forKey: .shareEnabled) ?? false
        self.shareAfterRefresh = try container.decodeIfPresent(Bool.self, forKey: .shareAfterRefresh) ?? false
        self.preferredShareAction = try container.decodeIfPresent(String.self, forKey: .preferredShareAction) ?? "publish"
        self.preferredUpdateAction = try container.decodeIfPresent(String.self, forKey: .preferredUpdateAction) ?? "update"
        self.showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        self.configValues = try container.decodeIfPresent([String: String].self, forKey: .configValues) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encodeIfPresent(self.binaryPath, forKey: .binaryPath)
        try container.encodeIfPresent(self.configPath, forKey: .configPath)
        try container.encodeIfPresent(self.refreshFrequency, forKey: .refreshFrequency)
        try container.encodeIfPresent(self.preferredRefreshAction, forKey: .preferredRefreshAction)
        try container.encode(self.autoRefreshEnabled, forKey: .autoRefreshEnabled)
        try container.encode(self.shareEnabled, forKey: .shareEnabled)
        try container.encode(self.shareAfterRefresh, forKey: .shareAfterRefresh)
        try container.encodeIfPresent(self.preferredShareAction, forKey: .preferredShareAction)
        try container.encodeIfPresent(self.preferredUpdateAction, forKey: .preferredUpdateAction)
        try container.encode(self.showInMenuBar, forKey: .showInMenuBar)
        if !self.configValues.isEmpty {
            try container.encode(self.configValues, forKey: .configValues)
        }
    }
}
