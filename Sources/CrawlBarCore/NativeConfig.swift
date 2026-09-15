import Foundation

public struct CrawlNativeConfigStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let cache: CrawlNativeConfigCache

    public init(fileManager: FileManager = .default, cache: CrawlNativeConfigCache = .shared) {
        self.fileManager = fileManager
        self.cache = cache
    }

    public func resolvedConfigValues(
        appConfig: CrawlBarAppConfig,
        manifest: CrawlAppManifest,
        includeSecrets: Bool = true)
        -> [String: String]
    {
        let path = self.configPath(appConfig: appConfig, manifest: manifest)
        let nativeValues = path.flatMap { self.cachedRead(path: $0, manifest: manifest) } ?? [:]
        let merged = nativeValues.merging(appConfig.configValues) { _, explicit in explicit }
        guard !includeSecrets else { return merged }
        let secretIDs = Set(manifest.configOptions.filter { $0.kind == .secret }.map(\.id))
        return merged.filter { !secretIDs.contains($0.key) }
    }

    public func write(
        appConfig: CrawlBarAppConfig,
        manifest: CrawlAppManifest,
        clearMissingSecretIDs: Set<String> = [])
        throws
    {
        guard manifest.configOptions.contains(where: { $0.configKey?.nilIfBlank != nil }),
              let path = self.configPath(appConfig: appConfig, manifest: manifest)
        else { return }
        try self.write(
            values: appConfig.configValues,
            manifest: manifest,
            path: path,
            clearMissingSecretIDs: clearMissingSecretIDs)
        self.cache.remove(path: PathExpander.expandHome(path), appID: manifest.id)
    }

    public func write(
        config: CrawlBarConfig,
        clearMissingSecretIDsByAppID: [CrawlAppID: Set<String>] = [:])
        throws
    {
        let manifests = Dictionary(uniqueKeysWithValues: CrawlManifestCatalog(fileManager: self.fileManager)
            .manifests(config: config)
            .map { ($0.id, $0) })
        for appConfig in config.apps {
            guard let manifest = manifests[appConfig.id] else { continue }
            try self.write(
                appConfig: appConfig,
                manifest: manifest,
                clearMissingSecretIDs: clearMissingSecretIDsByAppID[appConfig.id] ?? [])
        }
    }

    public func read(path: String, manifest: CrawlAppManifest) throws -> [String: String] {
        guard self.fileManager.fileExists(atPath: path) else { return [:] }
        let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let arrayPaths = Self.arrayTablePaths(in: lines)
        var values: [String: String] = [:]
        var section: String? = ""
        var optionIDsByConfigKey: [String: String] = [:]
        for option in manifest.configOptions {
            guard let key = option.configKey?.nilIfBlank,
                  optionIDsByConfigKey[key] == nil
            else { continue }
            optionIDsByConfigKey[key] = option.id
        }
        for index in Self.statementIndices(in: lines) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if let header = Self.tableHeader(trimmed) {
                section = header.isArray ? nil : header.name
                continue
            }
            guard let section, let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let fullKey = section.isEmpty ? key : "\(section).\(key)"
            guard !Self.isArrayValue(fullKey, arrayPaths: arrayPaths) else { continue }
            guard let optionID = optionIDsByConfigKey[fullKey] else { continue }
            let raw = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            values[optionID] = Self.decodeTomlScalar(raw)
        }
        return values
    }

    func publicationValues(path: String, manifest: CrawlAppManifest, optionIDs: Set<String>) throws -> [String: String] {
        guard self.fileManager.fileExists(atPath: path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try self.read(path: path, manifest: manifest).filter { optionIDs.contains($0.key) }
    }

    private func cachedRead(path: String, manifest: CrawlAppManifest) -> [String: String] {
        let expandedPath = PathExpander.expandHome(path)
        guard self.fileManager.fileExists(atPath: expandedPath) else { return [:] }
        let modificationDate = (try? URL(fileURLWithPath: expandedPath).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let manifestSignature = Self.configOptionSignature(for: manifest)
        if let cached = self.cache.values(
            path: expandedPath,
            appID: manifest.id,
            manifestSignature: manifestSignature,
            modificationDate: modificationDate)
        {
            return cached
        }
        let values = (try? self.read(path: expandedPath, manifest: manifest)) ?? [:]
        self.cache.set(
            values,
            path: expandedPath,
            appID: manifest.id,
            manifestSignature: manifestSignature,
            modificationDate: modificationDate)
        return values
    }

    private static func configOptionSignature(for manifest: CrawlAppManifest) -> String {
        manifest.configOptions
            .compactMap { option in
                option.configKey?.nilIfBlank.map { "\(option.id)=\($0)" }
            }
            .joined(separator: "\u{0}")
    }

    private func write(
        values: [String: String],
        manifest: CrawlAppManifest,
        path: String,
        clearMissingSecretIDs: Set<String>)
        throws
    {
        let url = URL(fileURLWithPath: PathExpander.expandHome(path))
        let hasWritableValues = manifest.configOptions.contains { option in
            guard option.configKey?.nilIfBlank != nil else { return false }
            return values[option.id]?.nilIfBlank != nil
        }
        guard self.fileManager.fileExists(atPath: url.path) || hasWritableValues else { return }
        let directory = url.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var lines: [String]
        if self.fileManager.fileExists(atPath: url.path) {
            lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        } else {
            lines = []
        }

        let originalLines = lines
        let arrayPaths = Self.arrayTablePaths(in: lines)
        for option in manifest.configOptions {
            guard let configKey = option.configKey?.nilIfBlank else { continue }
            // Saved overrides are still valid, but scalar writes cannot select an array element.
            guard !Self.isArrayValue(configKey, arrayPaths: arrayPaths) else { continue }
            guard let value = values[option.id]?.nilIfBlank else {
                if option.kind == .secret, !clearMissingSecretIDs.contains(option.id) {
                    continue
                }
                Self.remove(configKey: configKey, in: &lines)
                continue
            }
            Self.set(configKey: configKey, value: Self.encodeTomlScalar(value, kind: option.kind), in: &lines)
        }

        if lines != originalLines {
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        try self.fileManager.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: url.path)
    }

    private func configPath(appConfig: CrawlBarAppConfig, manifest: CrawlAppManifest) -> String? {
        (appConfig.configPath?.nilIfBlank ?? manifest.paths.defaultConfig?.nilIfBlank)
            .map { PathExpander.expandHome($0) }
    }

    private static func set(configKey: String, value: String, in lines: inout [String]) {
        let parts = configKey.split(separator: ".").map(String.init)
        guard let key = parts.last else { return }
        let section = parts.dropLast().joined(separator: ".")
        let sectionRange = Self.sectionRange(section, in: lines)
        let keyLine = "\(key) = \(value)"

        if let sectionRange {
            for index in Self.statementIndices(in: lines) where sectionRange.contains(index) {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                guard let equals = trimmed.firstIndex(of: "=") else { continue }
                let existingKey = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
                if existingKey == key {
                    lines[index] = keyLine
                    return
                }
            }
            lines.insert(keyLine, at: sectionRange.upperBound)
            return
        }

        if !section.isEmpty {
            if !lines.isEmpty, lines.last?.nilIfBlank != nil {
                lines.append("")
            }
            lines.append("[\(section)]")
        }
        lines.append(keyLine)
    }

    private static func remove(configKey: String, in lines: inout [String]) {
        let parts = configKey.split(separator: ".").map(String.init)
        guard let key = parts.last else { return }
        let section = parts.dropLast().joined(separator: ".")
        guard let sectionRange = Self.sectionRange(section, in: lines) else { return }
        for index in Self.statementIndices(in: lines) where sectionRange.contains(index) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let existingKey = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            if existingKey == key {
                lines.remove(at: index)
                return
            }
        }
    }

    private static func sectionRange(_ section: String, in lines: [String]) -> Range<Int>? {
        let statements = Self.statementIndices(in: lines)
        if section.isEmpty {
            let end = statements.first { Self.tableHeader(lines[$0]) != nil } ?? lines.count
            return 0..<end
        }

        var start: Int?
        for index in statements {
            guard let header = Self.tableHeader(lines[index]) else { continue }
            if !header.isArray, header.name == section {
                start = index + 1
                continue
            }
            if let start {
                return start..<index
            }
        }
        guard let start else { return nil }
        return start..<lines.count
    }

    private static func tableHeader(_ line: String) -> (name: String, isArray: Bool)? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("[") else { return nil }
        let isArray = text.hasPrefix("[[")
        let start = text.index(text.startIndex, offsetBy: isArray ? 2 : 1)
        var quote: Character?
        var escaped = false
        for index in text[start...].indices {
            let character = text[index]
            if let currentQuote = quote {
                if escaped {
                    escaped = false
                } else if currentQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == currentQuote {
                    quote = nil
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            guard character == "]" else { continue }
            var end = text.index(after: index)
            if isArray {
                guard end < text.endIndex, text[end] == "]" else { return nil }
                end = text.index(after: end)
            }
            let suffix = text[end...].trimmingCharacters(in: .whitespaces)
            guard suffix.isEmpty || suffix.hasPrefix("#") else { return nil }
            return (String(text[start..<index]).trimmingCharacters(in: .whitespaces), isArray)
        }
        return nil
    }

    private static func arrayTablePaths(in lines: [String]) -> [[String]] {
        Self.statementIndices(in: lines).compactMap { index in
            guard let header = Self.tableHeader(lines[index]), header.isArray else { return nil }
            return Self.keyPathComponents(header.name)
        }
    }

    private static func isArrayValue(_ key: String, arrayPaths: [[String]]) -> Bool {
        let components = Self.keyPathComponents(key)
        return arrayPaths.contains { components.starts(with: $0) }
    }

    private static func encodeTomlScalar(_ value: String, kind: CrawlAppManifest.ConfigOptionKind) -> String {
        if kind == .boolean {
            return ["1", "true", "yes", "on"].contains(value.lowercased()) ? "true" : "false"
        }
        if kind == .number {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "0"
        }
        return "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func decodeTomlScalar(_ value: String) -> String {
        if value == "true" || value == "false" { return value }
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
            return value
        }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

public final class CrawlNativeConfigCache: @unchecked Sendable {
    public static let shared = CrawlNativeConfigCache()

    private struct Entry {
        var modificationDate: Date?
        var values: [String: String]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    func values(path: String, appID: CrawlAppID, manifestSignature: String, modificationDate: Date?) -> [String: String]? {
        let key = self.key(path: path, appID: appID, manifestSignature: manifestSignature)
        return self.lock.withLock {
            guard let entry = self.entries[key], entry.modificationDate == modificationDate else {
                return nil
            }
            return entry.values
        }
    }

    func set(_ values: [String: String], path: String, appID: CrawlAppID, manifestSignature: String, modificationDate: Date?) {
        let key = self.key(path: path, appID: appID, manifestSignature: manifestSignature)
        self.lock.withLock {
            self.entries[key] = Entry(modificationDate: modificationDate, values: values)
        }
    }

    func remove(path: String, appID: CrawlAppID) {
        self.lock.withLock {
            self.entries = self.entries.filter { key, _ in
                !key.hasPrefix("\(appID.rawValue)\u{0}\(path)\u{0}")
            }
        }
    }

    private func key(path: String, appID: CrawlAppID, manifestSignature: String) -> String {
        "\(appID.rawValue)\u{0}\(path)\u{0}\(manifestSignature)"
    }
}
