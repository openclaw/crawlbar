import Foundation

public struct CrawlCommandRedactor: Sendable {
    public init() {}

    public func redact(_ text: String) -> String {
        var redacted = text
        let patterns: [(String, String)] = [
            (#"(?i)(Bearer[ \t]+)[^ \t\r\n"',}]+"#, "$1[REDACTED]"),
            (#"(?i)(api[_-]?key|token|secret|password|cookie|authorization)(["' \t:=]+)([^ \t\r\n"',}]+)"#, "$1$2[REDACTED]"),
            (#"(?i)\b(github_pat_)[A-Za-z0-9_]+\b"#, "$1[REDACTED]"),
            (#"(?i)\b(gh[pousr]_)[A-Za-z0-9_]+\b"#, "$1[REDACTED]"),
            (#"(?i)\b(sk-[A-Za-z0-9_-]{16,})\b"#, "[REDACTED]"),
            (#"(?i)\b(secret_)[A-Za-z0-9_]+\b"#, "$1[REDACTED]"),
            (#"(?i)(xox[aboprsxc]-)[A-Za-z0-9-]+"#, "$1[REDACTED]"),
            (#"(?i)\bmfa\.[A-Za-z0-9_-]+\b"#, "[REDACTED]"),
            (#"(?i)\b(ct0)(["' \t:=]+)([^ \t\r\n"',}]+)"#, "$1$2[REDACTED]"),
            (#"\b[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{20,}\b"#, "[REDACTED]"),
            (#"(?i)(discord[_-]?token["' \t:=]+)([^ \t\r\n"',}]+)"#, "$1[REDACTED]"),
        ]
        for (pattern, template) in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: template,
                options: [.regularExpression])
        }
        return redacted
    }
}
