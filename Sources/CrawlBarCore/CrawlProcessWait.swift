import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

package enum CrawlProcessWait {
    package static let timeoutTerminationGrace: TimeInterval = 0.5

    package enum Outcome: Equatable, Sendable {
        case exited
        case timedOut
    }

    @discardableResult
    package static func waitUntilExit(_ process: Process, timeoutSeconds: TimeInterval) -> Outcome {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        if !process.isRunning {
            return .exited
        }
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .success {
            return .exited
        }

        process.terminate()
        if semaphore.wait(timeout: .now() + Self.timeoutTerminationGrace) == .success {
            return .timedOut
        }

        #if os(macOS) || os(Linux)
        let pid = process.processIdentifier
        if process.isRunning, pid > 0 {
            kill(pid, SIGKILL)
        }
        #endif
        _ = semaphore.wait(timeout: .now() + Self.timeoutTerminationGrace)
        return .timedOut
    }
}
