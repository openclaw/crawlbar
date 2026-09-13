import CryptoKit
import Foundation

package enum CrawlActionCoordinatorError: LocalizedError {
    case busy
    case notDue

    package var errorDescription: String? {
        switch self {
        case .busy: "An action is already running for this crawler"
        case .notDue: "The scheduled action is not due"
        }
    }
}

package struct CrawlActionOutcome: Sendable {
    package let results: [CrawlCommandResult]
    package let failure: CrawlAppStatus?
    package let generation: UInt64
}

// One in-process owner for menu/settings mutations. Archive writers still need
// their own cross-process exclusion; independent status reads bypass this gate.
package final class CrawlActionCoordinator: @unchecked Sendable {
    package static let shared = CrawlActionCoordinator()

    private struct PublishIdentity: Equatable {
        let installation: CrawlAppInstallation
        let refreshAction: String
        let shareAction: String
        let configDigest: Data
    }

    private let lock = NSLock()
    private var running: Set<CrawlAppID> = []
    private var attempts: [CrawlAppID: Date] = [:]
    private var successes: [CrawlAppID: Date] = [:]
    private var generations: [CrawlAppID: UInt64] = [:]
    private var pendingPublish: [CrawlAppID: PublishIdentity] = [:]

    package init() {}

    package func isDue(_ appID: CrawlAppID, interval: TimeInterval, now: Date = Date()) -> Bool {
        self.lock.withLock {
            !self.running.contains(appID)
                && now.timeIntervalSince(self.attempts[appID] ?? .distantPast) >= interval
        }
    }

    package func isCurrent(_ appID: CrawlAppID, generation: UInt64) -> Bool {
        self.lock.withLock { self.generations[appID] == generation }
    }

    package func lastSuccessfulSync(_ appID: CrawlAppID) -> Date? {
        self.lock.withLock { self.successes[appID] }
    }

    package func run(
        installation: CrawlAppInstallation,
        config: CrawlBarAppConfig,
        configValues: [String: String],
        action: String,
        now: Date = Date(),
        scheduledInterval: TimeInterval? = nil,
        allowShare: () -> Bool = { true },
        execute: (String) throws -> CrawlCommandResult)
        throws -> CrawlActionOutcome
    {
        let appID = installation.id
        let refreshAction = config.preferredRefreshAction ?? "refresh"
        let shareAction = config.preferredShareAction ?? "publish"
        let refresh = action == refreshAction
        let share = refresh && config.shareEnabled && config.shareAfterRefresh
        let digest = Data(SHA256.hash(data: try JSONSerialization.data(withJSONObject: configValues, options: [.sortedKeys])))
        let identity = PublishIdentity(
            installation: installation, refreshAction: refreshAction,
            shareAction: shareAction, configDigest: digest)
        let (generation, resumePublish) = try self.lock.withLock {
            guard !self.running.contains(appID) else { throw CrawlActionCoordinatorError.busy }
            if let scheduledInterval, now.timeIntervalSince(self.attempts[appID] ?? .distantPast) < scheduledInterval {
                throw CrawlActionCoordinatorError.notDue
            }
            self.running.insert(appID)
            if refresh { self.attempts[appID] = now }
            let generation = (self.generations[appID] ?? 0) &+ 1
            self.generations[appID] = generation
            let resume = scheduledInterval != nil && share && self.pendingPublish[appID] == identity
            if self.pendingPublish[appID] != identity || !config.shareEnabled || !config.shareAfterRefresh
                || (refresh && !resume) || (!refresh && action != shareAction)
            {
                self.pendingPublish[appID] = nil
            }
            return (generation, resume)
        }
        defer { _ = self.lock.withLock { self.running.remove(appID) } }

        var actions = resumePublish ? [shareAction] : [action]
        if share && !resumePublish && shareAction != action { actions.append(shareAction) }
        var results: [CrawlCommandResult] = []
        for next in actions {
            if Task.isCancelled {
                return CrawlActionOutcome(
                    results: results,
                    failure: .commandFailure(appID: appID, action: next, message: "Action cancelled", fallback: "Action cancelled"),
                    generation: generation)
            }
            if next == shareAction && share && !allowShare() {
                self.lock.withLock { self.pendingPublish[appID] = nil }
                break
            }
            do {
                let result = try execute(next)
                results.append(result)
                guard result.succeeded else {
                    return CrawlActionOutcome(
                        results: results,
                        failure: .commandFailure(
                            appID: appID, action: next,
                            message: result.stderr.nilIfBlank ?? result.stdout.nilIfBlank,
                            fallback: "\(next) failed with exit \(result.exitCode)"),
                        generation: generation)
                }
                self.lock.withLock {
                    if next == refreshAction {
                        self.successes[appID] = result.finishedAt
                        self.pendingPublish[appID] = share ? identity : nil
                    }
                    if next == shareAction { self.pendingPublish[appID] = nil }
                }
            } catch {
                return CrawlActionOutcome(
                    results: results,
                    failure: .commandFailure(
                        appID: appID, action: next, message: error.localizedDescription,
                        fallback: "\(next) failed"),
                    generation: generation)
            }
        }
        return CrawlActionOutcome(results: results, failure: nil, generation: generation)
    }
}
