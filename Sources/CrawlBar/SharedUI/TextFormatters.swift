import CrawlBarCore
import Foundation

enum CrawlBarFrequencyLabel {
    static func text(for frequency: RefreshFrequency) -> String {
        switch frequency {
        case .manual:
            "Manual"
        case .fiveMinutes:
            "5 minutes"
        case .fifteenMinutes:
            "15 minutes"
        case .thirtyMinutes:
            "30 minutes"
        case .hourly:
            "Hourly"
        }
    }
}

@MainActor
enum CrawlBarDateText {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relative(_ date: Date) -> String {
        self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

enum CrawlBarFileSizeText {
    private static let formatter = CrawlBarLockedByteCountFormatter()

    static func string(fromByteCount byteCount: Int64) -> String {
        self.formatter.string(fromByteCount: byteCount)
    }
}

private final class CrawlBarLockedByteCountFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter
    }()

    func string(fromByteCount byteCount: Int64) -> String {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.formatter.string(fromByteCount: byteCount)
    }
}
