import Foundation

package struct CrawlManifestDiagnostic: Codable, Equatable, Sendable, Identifiable {
    package var path: String
    package var message: String

    package var id: String {
        self.path
    }

    package init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

package struct CrawlManifestCatalog: @unchecked Sendable {
    private let fileManager: FileManager
    private let scanCache: CrawlManifestScanCache

    package init(fileManager: FileManager = .default) {
        self.init(fileManager: fileManager, scanCache: .shared)
    }

    private init(fileManager: FileManager, scanCache: CrawlManifestScanCache) {
        self.fileManager = fileManager
        self.scanCache = scanCache
    }

    package func manifests(config: CrawlBarConfig) -> [CrawlAppManifest] {
        var manifestsByID = BuiltInCrawlApps.allByID
        for manifest in self.externalManifestScan(directories: config.manifestDirectories).manifests {
            manifestsByID[manifest.id] = manifest
        }
        return manifestsByID.values.sorted { $0.id < $1.id }
    }

    package func manifest(for id: CrawlAppID, config: CrawlBarConfig) -> CrawlAppManifest? {
        self.manifests(config: config).first { $0.id == id }
    }

    package func diagnostics(config: CrawlBarConfig) -> [CrawlManifestDiagnostic] {
        self.externalManifestScan(directories: config.manifestDirectories).diagnostics
    }

    private func externalManifestScan(directories: [String]) -> (manifests: [CrawlAppManifest], diagnostics: [CrawlManifestDiagnostic]) {
        self.scanCache.scan(directories: directories) {
            self.externalManifestScanUncached(directories: directories)
        }
    }

    private func externalManifestScanUncached(directories: [String]) -> (manifests: [CrawlAppManifest], diagnostics: [CrawlManifestDiagnostic]) {
        var manifests: [CrawlAppManifest] = []
        var diagnostics: [CrawlManifestDiagnostic] = []

        for directory in directories {
            let expanded = PathExpander.expandHome(directory)
            guard let enumerator = self.fileManager.enumerator(
                at: URL(fileURLWithPath: expanded, isDirectory: true),
                includingPropertiesForKeys: nil)
            else {
                continue
            }

            for item in enumerator {
                guard let url = item as? URL, url.pathExtension == "json" else { continue }
                do {
                    let data = try Data(contentsOf: url)
                    manifests.append(try CrawlCoding.makeJSONDecoder().decode(CrawlAppManifest.self, from: data))
                } catch {
                    diagnostics.append(CrawlManifestDiagnostic(
                        path: url.path,
                        message: error.localizedDescription))
                }
            }
        }

        return (manifests, diagnostics)
    }
}

final class CrawlManifestScanCache: @unchecked Sendable {
    static let shared = CrawlManifestScanCache()

    private struct Entry {
        var loadedAt: Date
        var manifests: [CrawlAppManifest]
        var diagnostics: [CrawlManifestDiagnostic]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let timeToLive: TimeInterval

    init(timeToLive: TimeInterval = 2) {
        self.timeToLive = timeToLive
    }

    func scan(
        directories: [String],
        load: () -> (manifests: [CrawlAppManifest], diagnostics: [CrawlManifestDiagnostic]))
        -> (manifests: [CrawlAppManifest], diagnostics: [CrawlManifestDiagnostic])
    {
        let key = directories.map { PathExpander.expandHome($0) }.joined(separator: "\u{0}")
        let now = Date()
        self.lock.lock()
        if let entry = self.entries[key], now.timeIntervalSince(entry.loadedAt) < self.timeToLive {
            self.lock.unlock()
            return (entry.manifests, entry.diagnostics)
        }
        self.lock.unlock()

        let result = load()
        self.lock.lock()
        self.entries[key] = Entry(loadedAt: now, manifests: result.manifests, diagnostics: result.diagnostics)
        self.lock.unlock()
        return result
    }
}
