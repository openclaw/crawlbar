import AppKit

@MainActor
enum CrawlBarNativeAppLocator {
    private static var urlsByBundleIdentifier: [String: URL] = [:]

    static func url(for bundleIdentifier: String) -> URL? {
        if let cached = Self.urlsByBundleIdentifier[bundleIdentifier] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        Self.urlsByBundleIdentifier[bundleIdentifier] = url
        return url
    }
}
