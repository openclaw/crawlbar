import AppKit

@main
@MainActor
enum CrawlBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = CrawlBarAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
