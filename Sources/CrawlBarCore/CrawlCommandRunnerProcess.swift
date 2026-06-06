import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

extension CrawlCommandRunner {
    func runProcess(
        appID: CrawlAppID,
        action: String,
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval)
        throws -> CrawlCommandResult
    {
        let startedAt = Date()
        let tempDirectory = self.fileManager.temporaryDirectory
            .appendingPathComponent("crawlbar-\(UUID().uuidString)", isDirectory: true)
        try self.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? self.fileManager.removeItem(at: tempDirectory) }

        let stdoutURL = tempDirectory.appendingPathComponent("stdout.log")
        let stderrURL = tempDirectory.appendingPathComponent("stderr.log")
        self.fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        self.fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()
        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            #if os(macOS) || os(Linux)
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutTerminationGrace) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
            #endif
            process.waitUntilExit()
            throw CrawlCommandRunnerError.timedOut(
                appID: appID,
                action: action,
                seconds: Int(timeoutSeconds))
        }

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()

        let stdout = try String(contentsOf: stdoutURL, encoding: .utf8)
        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)
        return CrawlCommandResult(
            appID: appID,
            action: action,
            exitCode: process.terminationStatus,
            stdout: self.redactor.redact(stdout),
            stderr: self.redactor.redact(stderr),
            startedAt: startedAt,
            finishedAt: Date())
    }
}
