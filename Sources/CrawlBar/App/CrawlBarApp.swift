import AppKit

@main
@MainActor
enum CrawlBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = CrawlBarAppDelegate()
        app.delegate = delegate
        // Launch as a menu-bar app; Settings switches to regular activation while its window is open.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
