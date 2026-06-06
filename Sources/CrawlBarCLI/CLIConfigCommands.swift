import CrawlBarCore
import Foundation

extension CrawlBarCLI {
    static func runConfig(_ options: CLIOptions, registry: CrawlAppRegistry) throws {
        let store = CrawlBarConfigStore()
        let nativeConfigStore = CrawlNativeConfigStore()
        switch options.positionals.first {
        case "path":
            print(store.fileURL.path)
        case "validate":
            _ = try store.loadOrCreateDefault()
            print("ok")
        case "init", nil:
            let config = try store.loadOrCreateDefault()
            try CLIOutput.writeJSON(config)
        case "get":
            try Self.printConfigValue(
                options,
                registry: registry,
                store: store,
                nativeConfigStore: nativeConfigStore)
        case "set":
            try Self.setConfigValue(
                options,
                registry: registry,
                store: store,
                nativeConfigStore: nativeConfigStore)
        case let command?:
            throw CLIError.usage("unknown config command: \(command)")
        }
    }

    private static func printConfigValue(
        _ options: CLIOptions,
        registry: CrawlAppRegistry,
        store: CrawlBarConfigStore,
        nativeConfigStore: CrawlNativeConfigStore)
        throws
    {
        let appID = try options.requiredAppID()
        let config = try store.loadOrCreateDefault(includeSecrets: options.revealSecrets)
        let installation = try registry.installation(for: appID)
        let baseAppConfig = config.appConfig(for: appID) ?? CrawlBarAppConfig(id: appID)
        let appConfig = installation.map {
            var copy = baseAppConfig
            copy.configValues = nativeConfigStore.resolvedConfigValues(appConfig: baseAppConfig, manifest: $0.manifest)
            return copy
        } ?? baseAppConfig
        let values = Self.configValues(
            appConfig: appConfig,
            manifest: installation?.manifest,
            key: options.key,
            revealSecrets: options.revealSecrets)
        if options.json {
            try CLIOutput.writeJSON(values)
            return
        }
        if let key = options.key {
            guard let value = values.first else {
                throw CLIError.usage("unknown config key for \(appID.rawValue): \(key)")
            }
            print(value.value ?? "")
            return
        }
        for value in values {
            print("\(value.id)\t\(value.value ?? "")")
        }
    }

    private static func setConfigValue(
        _ options: CLIOptions,
        registry: CrawlAppRegistry,
        store: CrawlBarConfigStore,
        nativeConfigStore: CrawlNativeConfigStore)
        throws
    {
        let appID = try options.requiredAppID()
        guard let key = options.key?.nilIfBlank else {
            throw CLIError.usage("config set requires --key <id>")
        }
        guard let value = options.value else {
            throw CLIError.usage("config set requires --value <value>")
        }
        var config = try store.loadOrCreateDefault()
        guard let index = config.apps.firstIndex(where: { $0.id == appID }) else {
            throw CLIError.usage("unknown app: \(appID.rawValue)")
        }
        if value.nilIfBlank == nil {
            config.apps[index].configValues.removeValue(forKey: key)
        } else {
            config.apps[index].configValues[key] = value
        }
        let clearMissingSecretIDsByAppID: [CrawlAppID: Set<String>] = value.nilIfBlank == nil ? [appID: [key]] : [:]
        try store.save(config, clearMissingSecretIDsByAppID: clearMissingSecretIDsByAppID)
        if let installation = try registry.installation(for: appID),
           let appConfig = config.appConfig(for: appID)
        {
            var nativeAppConfig = appConfig
            var resolvedValues = nativeConfigStore.resolvedConfigValues(
                appConfig: appConfig,
                manifest: installation.manifest)
            if value.nilIfBlank == nil {
                resolvedValues.removeValue(forKey: key)
            } else {
                resolvedValues[key] = value
            }
            nativeAppConfig.configValues = resolvedValues
            try nativeConfigStore.write(
                appConfig: nativeAppConfig,
                manifest: installation.manifest,
                clearMissingSecretIDs: clearMissingSecretIDsByAppID[appID] ?? [])
        }
        if options.json {
            try CLIOutput.writeJSON(["app_id": appID.rawValue, "key": key, "updated": "true"])
            return
        }
        print("ok")
    }

    private static func configValues(
        appConfig: CrawlBarAppConfig,
        manifest: CrawlAppManifest?,
        key: String?,
        revealSecrets: Bool)
        -> [CLIConfigValue]
    {
        let options = manifest?.configOptions ?? []
        let knownIDs = Set(options.map(\.id))
        let extraOptions = appConfig.configValues.keys
            .filter { !knownIDs.contains($0) }
            .sorted()
            .map { CrawlAppManifest.ConfigOption(id: $0, label: $0) }
        return (options + extraOptions)
            .filter { key == nil || $0.id == key }
            .map { option in
                let rawValue = appConfig.configValues[option.id] ?? option.defaultValue
                let isSecret = option.kind == .secret
                return CLIConfigValue(
                    id: option.id,
                    label: option.label,
                    value: isSecret && !revealSecrets && rawValue?.nilIfBlank != nil ? "********" : rawValue,
                    secret: isSecret,
                    envVar: option.envVar,
                    configKey: option.configKey)
            }
    }
}
