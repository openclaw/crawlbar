import Foundation

public enum CrawlCommandRunnerError: LocalizedError, Sendable {
    case executableNotFound(String)
    case commandUnavailable(appID: CrawlAppID, action: String)
    case missingRequiredConfig(appID: CrawlAppID, optionID: String)
    case invalidConfigExpansion(appID: CrawlAppID)
    case invalidRemoteTarget(appID: CrawlAppID, target: String)
    case timedOut(appID: CrawlAppID, action: String, seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(name):
            "Could not find executable: \(name)"
        case let .commandUnavailable(appID, action):
            "\(appID.rawValue) does not expose a \(action) command"
        case let .missingRequiredConfig(appID, optionID):
            "\(appID.rawValue) is missing required config: \(optionID)"
        case let .invalidConfigExpansion(appID):
            "\(appID.rawValue) config interpolation contains a cycle or exceeds expansion limits"
        case let .invalidRemoteTarget(appID, target):
            "\(appID.rawValue) has an invalid SSH target: \(target)"
        case let .timedOut(appID, action, seconds):
            "\(appID.rawValue) \(action) timed out after \(seconds)s"
        }
    }
}
