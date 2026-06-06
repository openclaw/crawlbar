import Foundation
import CrawlBarCore

extension Notification.Name {
    static let crawlBarStatusesDidChange = Notification.Name("com.vincentkoc.CrawlBar.statusesDidChange")
    static let crawlBarConfigDidChange = Notification.Name("com.vincentkoc.CrawlBar.configDidChange")
}

enum CrawlBarNotificationUserInfo {
    static let statuses = "statuses"
}

enum CrawlBarStateBroadcast {
    static func statusesDidChange(_ statuses: [CrawlAppID: CrawlAppStatus]) {
        guard !statuses.isEmpty else { return }
        NotificationCenter.default.post(
            name: .crawlBarStatusesDidChange,
            object: nil,
            userInfo: [CrawlBarNotificationUserInfo.statuses: statuses])
    }

    static func configDidChange() {
        NotificationCenter.default.post(name: .crawlBarConfigDidChange, object: nil)
    }

    static func statuses(from notification: Notification) -> [CrawlAppID: CrawlAppStatus]? {
        notification.userInfo?[CrawlBarNotificationUserInfo.statuses] as? [CrawlAppID: CrawlAppStatus]
    }
}
