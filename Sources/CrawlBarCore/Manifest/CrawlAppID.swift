import Foundation

package struct CrawlAppID: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    package var rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }

    package var description: String {
        self.rawValue
    }

    package static func < (lhs: CrawlAppID, rhs: CrawlAppID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
