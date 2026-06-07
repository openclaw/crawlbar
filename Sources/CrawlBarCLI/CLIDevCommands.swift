import CrawlBarCore
import Foundation

extension CrawlBarCLI {
    static func runDev(_ options: CLIOptions, registry: CrawlAppRegistry) throws {
        switch options.positionals.first {
        case "register":
            try Self.registerDevBinary(options, registry: registry)
        case "unregister":
            try Self.unregisterDevBinary(options, registry: registry)
        case "list":
            try Self.listDevBinaries(options, registry: registry)
        case let command?:
            throw CLIError.usage("unknown dev command: \(command)")
        case nil:
            throw CLIError.usage("dev requires register, unregister, or list")
        }
    }

    private static func registerDevBinary(_ options: CLIOptions, registry: CrawlAppRegistry) throws {
        let appID = try options.requiredAppID()
        let binary = try Self.requiredDevBinaryPath(options.binary)
        let store = CrawlBarConfigStore()
        var config = try store.loadOrCreateDefault()

        guard try registry.installation(for: appID) != nil else {
            throw CLIError.usage("unknown app: \(appID.rawValue)")
        }

        let index = Self.ensureAppConfig(appID: appID, in: &config)
        config.apps[index].binaryPath = binary
        config.apps[index].enabled = true
        config.apps[index].showInMenuBar = true
        try store.save(config)

        try Self.printDevBinaryUpdate(
            appID: appID,
            binaryPath: binary,
            registry: CrawlAppRegistry(),
            json: options.json)
    }

    private static func unregisterDevBinary(_ options: CLIOptions, registry: CrawlAppRegistry) throws {
        let appID = try options.requiredAppID()
        let store = CrawlBarConfigStore()
        var config = try store.loadOrCreateDefault()

        guard try registry.installation(for: appID) != nil else {
            throw CLIError.usage("unknown app: \(appID.rawValue)")
        }

        let index = Self.ensureAppConfig(appID: appID, in: &config)
        config.apps[index].binaryPath = nil
        try store.save(config)

        try Self.printDevBinaryUpdate(
            appID: appID,
            binaryPath: nil,
            registry: CrawlAppRegistry(),
            json: options.json)
    }

    private static func listDevBinaries(_ options: CLIOptions, registry: CrawlAppRegistry) throws {
        let config = try registry.loadConfig()
        let installationsByID = Dictionary(uniqueKeysWithValues: try registry
            .installations(includeDisabled: true)
            .map { ($0.id, $0) })
        let rows = config.apps.compactMap { appConfig -> CLIDevBinary? in
            guard let configuredPath = appConfig.binaryPath?.nilIfBlank else { return nil }
            let installation = installationsByID[appConfig.id]
            return CLIDevBinary(
                appID: appConfig.id.rawValue,
                displayName: installation?.manifest.displayName ?? appConfig.id.rawValue,
                configuredBinaryPath: configuredPath,
                resolvedBinaryPath: installation?.binaryPath)
        }

        if options.json {
            try CLIOutput.writeJSON(rows)
            return
        }
        if rows.isEmpty {
            print("no dev binaries registered")
            return
        }
        for row in rows {
            let configured = row.configuredBinaryPath ?? "unset"
            let resolved = row.resolvedBinaryPath ?? "missing"
            print("\(row.appID)\t\(configured)\t\(resolved)")
        }
    }

    private static func requiredDevBinaryPath(_ value: String?) throws -> String {
        guard let value = value?.nilIfBlank else {
            throw CLIError.usage("dev register requires --binary <path>")
        }
        let expanded = PathExpander.expandHome(value)
        guard expanded.hasPrefix("/") else {
            throw CLIError.usage("--binary must be an absolute path or ~/ path")
        }
        guard FileManager.default.isExecutableFile(atPath: expanded) else {
            throw CLIError.usage("--binary is not executable: \(expanded)")
        }
        return value
    }

    private static func ensureAppConfig(appID: CrawlAppID, in config: inout CrawlBarConfig) -> Int {
        if let index = config.apps.firstIndex(where: { $0.id == appID }) {
            return index
        }
        config.apps.append(CrawlBarAppConfig(id: appID))
        return config.apps.index(before: config.apps.endIndex)
    }

    private static func printDevBinaryUpdate(
        appID: CrawlAppID,
        binaryPath: String?,
        registry: CrawlAppRegistry,
        json: Bool)
        throws
    {
        let installation = try registry.installation(for: appID)
        let output = CLIDevBinary(
            appID: appID.rawValue,
            displayName: installation?.manifest.displayName ?? appID.rawValue,
            configuredBinaryPath: binaryPath,
            resolvedBinaryPath: installation?.binaryPath)
        if json {
            try CLIOutput.writeJSON(output)
            return
        }
        if let binaryPath {
            print("registered\t\(appID.rawValue)\t\(binaryPath)")
        } else {
            print("unregistered\t\(appID.rawValue)")
        }
    }
}

struct CLIDevBinary: Encodable {
    var appID: String
    var displayName: String
    var configuredBinaryPath: String?
    var resolvedBinaryPath: String?

    private enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case displayName = "display_name"
        case configuredBinaryPath = "configured_binary_path"
        case resolvedBinaryPath = "resolved_binary_path"
    }
}
