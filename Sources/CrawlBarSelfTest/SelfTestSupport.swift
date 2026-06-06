import CrawlBarCore
import Foundation

extension CrawlBarSelfTest {
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SelfTestError.failed(message)
        }
    }

    static func createSQLiteDatabase(_ url: URL, value: String) throws {
        try Self.runSQLite(url, sql: "create table sample(value text); insert into sample(value) values('\(value)');")
    }

    static func sqliteValue(_ url: URL) throws -> String {
        try Self.runSQLite(url, sql: "select value from sample limit 1;")
    }

    @discardableResult
    static func runSQLite(_ url: URL, sql: String) throws -> String {
        guard let sqlitePath = CrawlExecutableResolver().resolve("sqlite3") else {
            throw SelfTestError.failed("sqlite3 is available")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = [url.path, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw SelfTestError.failed("sqlite3 failed: \(text)")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SelfTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            "selftest failed: \(message)"
        }
    }
}
