import AppKit
import CrawlBarCore
import SwiftUI

@MainActor
final class CrawlBarSettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: CrawlBarSettingsModel?
    var onClose: (() -> Void)?

    func show(appID: CrawlAppID? = nil) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            CrawlBarLog.app.debug("Opened settings in \(elapsedMilliseconds, privacy: .public)ms")
        }

        if let window {
            self.present(window)
            if let appID {
                self.model?.selectedAppID = appID
            }
            if let model = self.model {
                self.refreshStatusAfterPresentation(model: model, window: window)
            }
            return
        }

        let model: CrawlBarSettingsModel
        if let cachedModel = self.model {
            model = cachedModel
        } else {
            model = CrawlBarSettingsModel(loadImmediately: false)
            self.model = model
        }
        if let appID {
            model.selectedAppID = appID
        } else if model.selectedSidebarItem == nil {
            model.selectedSidebarItem = .general
        }
        model.isLoading = true
        model.lastError = nil
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CrawlBarSettingsLayout.minWindowWidth,
                height: CrawlBarSettingsLayout.minWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "CrawlBar Settings"
        window.setAccessibilityTitle("CrawlBar Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentMinSize = NSSize(
            width: CrawlBarSettingsLayout.minWindowWidth,
            height: CrawlBarSettingsLayout.minWindowHeight)
        window.contentViewController = NSHostingController(rootView: CrawlBarSettingsView(model: model))
        self.present(window)
        self.window = window
        model.loadForPresentation { [weak self, weak window] in
            guard let self, let window else { return }
            self.refreshStatusAfterPresentation(model: model, window: window)
        }
    }

    private func present(_ window: NSWindow) {
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    private func refreshStatusAfterPresentation(model: CrawlBarSettingsModel, window: NSWindow) {
        guard !model.isRefreshing else { return }
        Task { @MainActor in
            await Task.yield()
            guard self.window === window else { return }
            model.refreshAll()
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.model?.save()
            self.model?.scrubSecretConfigValues()
            self.window = nil
            self.onClose?()
        }
    }
}
