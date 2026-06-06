import CrawlBarCore
import Foundation
import SwiftUI

extension CrawlBarAppDetailView {
    var configurationSection: some View {
        CrawlBarDetailSection(title: "Configuration") {
            self.configuration
            self.paths
            self.privacy
        }
    }

    var paths: some View {
        CrawlBarPanel(title: "Paths") {
            CrawlBarControlRow(
                title: "Binary path override",
                caption: "Leave empty to resolve the CLI from PATH.")
            {
                TextField("Optional", text: self.optionalText(\.binaryPath))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(self.save)
            }
            CrawlBarControlRow(
                title: "Config path override",
                caption: "Leave empty to use the crawler default.")
            {
                TextField("Optional", text: self.optionalText(\.configPath))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(self.save)
            }
            CrawlBarFact(label: "Default Config", value: self.manifest?.paths.defaultConfig ?? "None")
            CrawlBarFact(label: "Default Database", value: self.status?.databasePath ?? self.manifest?.paths.defaultDatabase ?? "Unknown")
            CrawlBarFact(label: "Logs", value: self.manifest?.paths.defaultLogs ?? "Unknown")
        }
    }

    @ViewBuilder
    var configuration: some View {
        if self.manifest?.availability == .comingSoon {
            CrawlBarPanel(title: "Coming Soon") {
                CrawlBarFact(label: "CLI", value: self.manifest?.binary.name ?? self.app.id.rawValue)
                CrawlBarFact(label: "Config", value: self.manifest?.paths.defaultConfig ?? "Not declared")
            }
        } else if let manifest = self.manifest, !manifest.configOptions.isEmpty {
            ForEach(self.configSections(for: manifest)) { section in
                CrawlBarPanel(title: section.title, caption: section.caption) {
                    ForEach(section.options) { option in
                        CrawlBarConfigOptionField(
                            option: option,
                            value: self.configValueBinding(for: option),
                            disabledReason: self.configDisabledReason(for: option))
                    }
                }
            }
        }
    }

    var privacy: some View {
        CrawlBarPanel(title: "Privacy") {
            CrawlBarFact(
                label: "Private Messages",
                value: self.manifest?.privacy.containsPrivateMessages == true ? "Possible local data" : "Not declared")
            CrawlBarFact(label: "Local-only scopes", value: self.manifest?.privacy.localOnlyScopes.joined(separator: ", ").nilIfBlank ?? "None")
            CrawlBarFact(label: "Action logs", value: CrawlActionLogStore.defaultDirectory().path)
        }
    }

    var configSourceSummary: String {
        if let configPath = self.status?.configPath ?? self.app.configPath ?? self.manifest?.paths.defaultConfig {
            return URL(fileURLWithPath: configPath).lastPathComponent
        }
        return "None"
    }

    func optionalText(_ keyPath: WritableKeyPath<CrawlBarAppConfig, String?>) -> Binding<String> {
        Binding(
            get: { self.app[keyPath: keyPath] ?? "" },
            set: {
                self.app[keyPath: keyPath] = $0.nilIfBlank
                self.saveDebounced()
            })
    }

    func configValueBinding(for option: CrawlAppManifest.ConfigOption) -> Binding<String> {
        Binding(
            get: { self.app.configValues[option.id] ?? option.defaultValue ?? "" },
            set: {
                let value = $0.nilIfBlank
                self.app.configValues[option.id] = value
                self.configValueChanged(option, value)
            })
    }

    func configDisabledReason(for option: CrawlAppManifest.ConfigOption) -> String? {
        guard self.usesRemoteStore else { return nil }
        let optionText = [
            option.id,
            option.configKey,
            option.envVar,
        ].compactMap { $0?.lowercased() }.joined(separator: " ")
        guard optionText.contains("openai") || optionText.contains("embedding") else { return nil }
        return "Disabled while this crawler is using a remote store."
    }

    func configSections(for manifest: CrawlAppManifest) -> [CrawlBarConfigSection] {
        var optionsByID: [String: CrawlAppManifest.ConfigOption] = [:]
        for option in manifest.configOptions where optionsByID[option.id] == nil {
            optionsByID[option.id] = option
        }
        let sections = manifest.configSections.isEmpty
            ? [CrawlBarConfigSection(id: "config", title: "Configuration", optionIDs: manifest.configOptions.map(\.id))]
            : manifest.configSections.map {
                CrawlBarConfigSection(
                    id: $0.id,
                    title: $0.title,
                    caption: $0.caption,
                    optionIDs: $0.optionIDs)
            }

        let usedIDs = Set(sections.flatMap(\.optionIDs))
        let resolved = sections.compactMap { section -> CrawlBarConfigSection? in
            let options = section.optionIDs.compactMap { optionsByID[$0] }
            guard !options.isEmpty else { return nil }
            return section.resolved(options: options)
        }
        let extraOptions = manifest.configOptions.filter { !usedIDs.contains($0.id) }
        if extraOptions.isEmpty {
            return resolved
        }
        return resolved + [CrawlBarConfigSection(id: "advanced", title: "Advanced", optionIDs: [], options: extraOptions)]
    }
}
