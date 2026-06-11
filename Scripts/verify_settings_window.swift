#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

struct Arguments {
    let executablePath: String
    let windowTitle: String
    let timeoutSeconds: TimeInterval
    let closeWindow: Bool

    init(_ raw: [String]) throws {
        var executablePath: String?
        var windowTitle = "CrawlBar Settings"
        var timeoutSeconds: TimeInterval = 8
        var closeWindow = false
        var index = 1

        while index < raw.count {
            let argument = raw[index]
            switch argument {
            case "--executable":
                index += 1
                guard index < raw.count else { throw ArgumentError.missingValue(argument) }
                executablePath = raw[index]
            case "--title":
                index += 1
                guard index < raw.count else { throw ArgumentError.missingValue(argument) }
                windowTitle = raw[index]
            case "--timeout":
                index += 1
                guard index < raw.count, let value = TimeInterval(raw[index]) else {
                    throw ArgumentError.missingValue(argument)
                }
                timeoutSeconds = value
            case "--close":
                closeWindow = true
            default:
                throw ArgumentError.unknown(argument)
            }
            index += 1
        }

        guard let executablePath else { throw ArgumentError.missingValue("--executable") }
        self.executablePath = executablePath
        self.windowTitle = windowTitle
        self.timeoutSeconds = timeoutSeconds
        self.closeWindow = closeWindow
    }
}

enum ArgumentError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknown(String)

    var description: String {
        switch self {
        case .missingValue(let argument):
            "missing value for \(argument)"
        case .unknown(let argument):
            "unknown argument \(argument)"
        }
    }
}

struct ObservedWindow {
    let element: AXUIElement
    let title: String
    let role: String
    let subrole: String
}

func copyAttribute<T>(_ element: AXUIElement, _ attribute: String, as type: T.Type = T.self) -> T? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value as? T
}

func runningApplication(executablePath: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { app in
        app.executableURL?.path == executablePath
    }
}

func windows(for app: NSRunningApplication) throws -> [ObservedWindow] {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var windowsValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
    guard result == .success else {
        throw VerificationError.axWindows(result)
    }

    let windowElements = (windowsValue as? [AXUIElement]) ?? []
    return windowElements.map { window in
        ObservedWindow(
            element: window,
            title: copyAttribute(window, kAXTitleAttribute) ?? "",
            role: copyAttribute(window, kAXRoleAttribute) ?? "",
            subrole: copyAttribute(window, kAXSubroleAttribute) ?? "")
    }
}

func close(_ window: ObservedWindow) {
    guard let closeButton: AXUIElement = copyAttribute(window.element, kAXCloseButtonAttribute) else { return }
    AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
}

enum VerificationError: Error, CustomStringConvertible {
    case appNotRunning(String)
    case axWindows(AXError)
    case windowNotFound(String, [ObservedWindow])

    var description: String {
        switch self {
        case .appNotRunning(let path):
            return "app_not_running executable=\(path)"
        case .axWindows(let error):
            return "ax_windows_failed error=\(error.rawValue)"
        case .windowNotFound(let title, let windows):
            let observed = windows.map { "\($0.title)|\($0.role)|\($0.subrole)" }.joined(separator: ", ")
            return "settings_window_not_found expected=\(title) observed=[\(observed)]"
        }
    }
}

func verify(_ arguments: Arguments) throws {
    let deadline = Date().addingTimeInterval(arguments.timeoutSeconds)
    var lastWindows: [ObservedWindow] = []

    repeat {
        guard let app = runningApplication(executablePath: arguments.executablePath) else {
            Thread.sleep(forTimeInterval: 0.2)
            continue
        }

        lastWindows = try windows(for: app)
        if let settingsWindow = lastWindows.first(where: { $0.title == arguments.windowTitle }) {
            print("settings_window_loaded=true")
            print("pid=\(app.processIdentifier)")
            print("title=\(settingsWindow.title)")
            print("role=\(settingsWindow.role)")
            print("subrole=\(settingsWindow.subrole)")
            if arguments.closeWindow {
                close(settingsWindow)
                print("settings_window_closed=true")
            }
            return
        }

        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline

    if runningApplication(executablePath: arguments.executablePath) == nil {
        throw VerificationError.appNotRunning(arguments.executablePath)
    }
    throw VerificationError.windowNotFound(arguments.windowTitle, lastWindows)
}

do {
    try verify(try Arguments(CommandLine.arguments))
} catch {
    fputs("verify_settings_window_failed: \(error)\n", stderr)
    exit(1)
}
