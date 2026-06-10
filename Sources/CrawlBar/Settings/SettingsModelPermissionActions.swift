import AppKit

extension CrawlBarSettingsModel {
    func openPermissionSettings(permissionID: String) {
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        if let url = Self.permissionSettingsURL(permissionID: permissionID) ?? fallback {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated private static func permissionSettingsURL(permissionID: String) -> URL? {
        let paneID: String
        switch permissionID {
        case "full_disk_access":
            paneID = "Privacy_AllFiles"
        case "contacts":
            paneID = "Privacy_Contacts"
        case "photos":
            paneID = "Privacy_Photos"
        case "calendars":
            paneID = "Privacy_Calendars"
        case "reminders":
            paneID = "Privacy_Reminders"
        default:
            return nil
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(paneID)")
    }
}
