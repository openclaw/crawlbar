import Foundation

public struct CrawlManifestDiagnostic: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var message: String

    public var id: String {
        self.path
    }

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct CrawlManifestCatalog: @unchecked Sendable {
    private let fileManager: FileManager
    private let scanCache: CrawlManifestScanCache

    public init(fileManager: FileManager = .default, scanCache: CrawlManifestScanCache = .shared) {
        self.fileManager = fileManager
        self.scanCache = scanCache
    }

    public func manifests(config: CrawlBarConfig) -> [CrawlAppManifest] {
        var manifestsByID = BuiltInCrawlApps.allByID
        for manifest in self.externalManifestScan(directories: config.manifestDirectories).manifests {
            manifestsByID[manifest.id] = manifest
        }
        return manifestsByID.values.sorted { $0.id < $1.id }
    }

    public func manifest(for id: CrawlAppID, config: CrawlBarConfig) -> CrawlAppManifest? {
        self.manifests(config: config).first { $0.id == id }
    }

    public func diagnostics(config: CrawlBarConfig) -> [CrawlManifestDiagnostic] {
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

public final class CrawlManifestScanCache: @unchecked Sendable {
    public static let shared = CrawlManifestScanCache()

    private struct Entry {
        var loadedAt: Date
        var manifests: [CrawlAppManifest]
        var diagnostics: [CrawlManifestDiagnostic]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let timeToLive: TimeInterval

    public init(timeToLive: TimeInterval = 2) {
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
