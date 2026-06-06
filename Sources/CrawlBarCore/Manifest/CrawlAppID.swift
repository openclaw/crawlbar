import Foundation

public struct CrawlAppID: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        self.rawValue
    }

    public static func < (lhs: CrawlAppID, rhs: CrawlAppID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
