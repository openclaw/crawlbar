import CrawlBarCore
import Foundation

struct CLIConfigValue: Encodable {
    var id: String
    var label: String
    var value: String?
    var secret: Bool
    var envVar: String?
    var configKey: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case value
        case secret
        case envVar = "env_var"
        case configKey = "config_key"
    }
}

struct CLIApp: Encodable {
    var id: String
    var displayName: String
    var enabled: Bool
    var available: Bool
    var availability: CrawlAppManifest.Availability
    var binaryPath: String?
    var configPath: String?

    init(_ installation: CrawlAppInstallation) {
        self.id = installation.id.rawValue
        self.displayName = installation.manifest.displayName
        self.enabled = installation.enabled
        self.available = installation.binaryPath != nil
        self.availability = installation.manifest.availability
        self.binaryPath = installation.binaryPath
        self.configPath = installation.configPathOverride
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case enabled
        case available
        case availability
        case binaryPath = "binary_path"
        case configPath = "config_path"
    }
}

struct CLIOptions {
    var json = false
    var appID: CrawlAppID?
    var binary: String?
    var key: String?
    var value: String?
    var revealSecrets = false
    var diagnostics = false
    var positionals: [String] = []

    init(_ arguments: ArraySlice<String>) {
        var iterator = Array(arguments).makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--json":
                self.json = true
            case "--app":
                if let value = iterator.next() {
                    self.appID = CrawlAppID(rawValue: value)
                }
            case "--binary":
                self.binary = iterator.next()
            case "--key":
                self.key = iterator.next()
            case "--value":
                self.value = iterator.next()
            case "--reveal":
                self.revealSecrets = true
            case "--diagnostics":
                self.diagnostics = true
            case "--":
                while let value = iterator.next() {
                    self.positionals.append(value)
                }
            default:
                self.positionals.append(argument)
            }
        }
    }

    func requiredAppID() throws -> CrawlAppID {
        guard let appID else {
            throw CLIError.usage("--app <id> is required")
        }
        return appID
    }
}

enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message):
            message
        }
    }
}
