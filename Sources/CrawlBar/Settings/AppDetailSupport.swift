import CrawlBarCore
import Foundation

struct CrawlBarConfigSection: Identifiable {
    var id: String
    var title: String
    var caption: String?
    var optionIDs: [String]
    var options: [CrawlAppManifest.ConfigOption]

    init(
        id: String,
        title: String,
        caption: String? = nil,
        optionIDs: [String],
        options: [CrawlAppManifest.ConfigOption] = [])
    {
        self.id = id
        self.title = title
        self.caption = caption
        self.optionIDs = optionIDs
        self.options = options
    }

    func resolved(options: [CrawlAppManifest.ConfigOption]) -> CrawlBarConfigSection {
        CrawlBarConfigSection(
            id: self.id,
            title: self.title,
            caption: self.caption,
            optionIDs: self.optionIDs,
            options: options)
    }
}

struct CrawlBarRemoteStoreSummary {
    enum Kind {
        case gitSnapshot
        case cloudflare
    }

    var remote: String
    var archive: String? = nil
    var repoPath: String? = nil
    var branch: String? = nil
    var kind: Kind
    var sqliteBundle: CrawlSQLiteBundleStatus? = nil
    var sqliteObject: CrawlSQLiteObjectStatus? = nil
    var lastIngestAt: Date? = nil

    var title: String {
        switch self.kind {
        case .cloudflare:
            "Cloudflare Archive"
        case .gitSnapshot:
            "Remote Store"
        }
    }

    var shortName: String {
        if self.kind == .cloudflare {
            return self.archive?.nilIfBlank ?? "Cloudflare archive"
        }
        let trimmed = self.remote
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .nilIfBlank
        return trimmed ?? "Remote store"
    }

    var dataScope: String {
        switch self.kind {
        case .cloudflare:
            "Cloudflare remote"
        case .gitSnapshot:
            "Remote store"
        }
    }

    var databaseSummary: String {
        guard self.kind == .cloudflare else { return self.shortName }
        let pieces = [
            self.shortName,
            self.sqliteBundle?.compressedBytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) },
            self.sqliteBundle?.compression?.nilIfBlank,
        ].compactMap { $0 }
        return pieces.isEmpty ? "Cloudflare archive" : pieces.joined(separator: " · ")
    }

    var bundle: String? {
        guard let sqliteBundle else { return nil }
        return [
            sqliteBundle.format?.nilIfBlank,
            sqliteBundle.compression?.nilIfBlank,
        ].compactMap { $0 }.joined(separator: " · ").nilIfBlank
    }

    var compressed: String? {
        let values = [
            sqliteBundle?.compressedBytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) },
            sqliteBundle?.rawBytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) + " raw" },
            sqliteObject?.bytes.map { CrawlBarFileSizeText.string(fromByteCount: Int64($0)) + " object" },
        ].compactMap { $0?.nilIfBlank }
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }

    var parts: String? {
        sqliteBundle?.partCount.map { "\($0)" }
    }

    var lastIngest: String? {
        guard let lastIngestAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastIngestAt, relativeTo: Date())
    }
}

extension CrawlBarAppDetailView {
    var installButtonTitle: String {
        switch self.manifest?.install?.method {
        case .homebrew:
            "Install with Homebrew"
        case nil:
            "Install"
        }
    }
}
