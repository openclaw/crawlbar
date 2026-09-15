import Foundation

extension CrawlStatusMapper {
    func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func intValue(_ keys: [String], in object: [String: Any]) -> Int? {
        for key in keys {
            if let value = self.firstValue(key, in: object), let int = self.int(value) {
                return int
            }
        }
        return nil
    }

    func boolValue(_ keys: [String], in object: [String: Any]) -> Bool? {
        for key in keys {
            guard let value = self.firstValue(key, in: object) else { continue }
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
            if let string = value as? String {
                switch string.lowercased() {
                case "true", "yes", "1":
                    return true
                case "false", "no", "0":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    func stringValue(_ keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = self.firstValue(key, in: object) as? String, let string = value.nilIfBlank {
                return string
            }
        }
        return nil
    }

    func statusValue(_ keys: [String], in object: [String: Any]) -> CrawlAppState? {
        guard let rawValue = self.stringValue(keys, in: object) else { return nil }
        if let state = CrawlAppState(rawValue: rawValue) {
            return state
        }
        switch rawValue.lowercased() {
        case "ok", "success", "healthy", "ready":
            return .current
        case "warn", "warning", "degraded":
            return .stale
        case "failed", "failure", "source_error", "archive_error":
            return .error
        case "missing":
            return .needsConfig
        default:
            return .unknown
        }
    }

    func stringValues(_ keys: [String], in object: [String: Any]) -> [String] {
        for key in keys {
            guard let values = self.firstValue(key, in: object) as? [Any] else { continue }
            return values.compactMap { ($0 as? String)?.nilIfBlank }
        }
        return []
    }

    func dateValue(_ keys: [String], in object: [String: Any]) -> Date? {
        for key in keys {
            guard let value = self.firstValue(key, in: object) else { continue }
            if let date = self.date(value) {
                return date
            }
        }
        return nil
    }

    func firstObject(_ keys: [String], in object: [String: Any]) -> [String: Any]? {
        for key in keys {
            if let object = self.firstValue(key, in: object) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    func firstValue(_ key: String, in object: [String: Any]) -> Any? {
        if let value = object[key] { return value }
        for value in object.values {
            if let nested = value as? [String: Any], let match = self.firstValue(key, in: nested) {
                return match
            }
        }
        return nil
    }

    func int(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    func date(_ value: Any) -> Date? {
        let parsed: Date?
        if let date = value as? Date {
            parsed = date
        } else if let number = value as? NSNumber {
            parsed = self.epochDate(number.doubleValue)
        } else if let string = value as? String, let trimmed = string.nilIfBlank {
            parsed = ISO8601DateFormatter.crawlBarDate(from: trimmed)
                ?? Double(trimmed).map { self.epochDate($0) }
        } else {
            return nil
        }
        // Keep crawler dates within four-digit ISO years, safe for age arithmetic and JSON output.
        guard let parsed,
              parsed.timeIntervalSince1970.isFinite,
              (-62_135_596_800..<253_402_300_800).contains(parsed.timeIntervalSince1970)
        else { return nil }
        return parsed
    }

    private func epochDate(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value > 99_999_999_999 ? value / 1_000 : value)
    }

    func label(from key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
