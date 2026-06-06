import Foundation

public enum CrawlBarConfigStoreError: LocalizedError {
    case decodeFailed(String)
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .decodeFailed(details):
            "Failed to decode CrawlBar config: \(details)"
        case let .encodeFailed(details):
            "Failed to encode CrawlBar config: \(details)"
        }
    }
}
