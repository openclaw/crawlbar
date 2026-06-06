import Foundation

public enum RefreshFrequency: String, Codable, CaseIterable, Sendable {
    case manual
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case hourly = "1h"

    public var seconds: TimeInterval? {
        switch self {
        case .manual:
            nil
        case .fiveMinutes:
            300
        case .fifteenMinutes:
            900
        case .thirtyMinutes:
            1_800
        case .hourly:
            3_600
        }
    }
}
