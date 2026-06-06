import CrawlBarCore
import Foundation

@MainActor
final class CrawlBarSettingsModel: NSObject, ObservableObject {
    @Published var apps: [CrawlBarAppConfig] = []
    @Published var refreshFrequency: RefreshFrequency = .fifteenMinutes
    @Published var selectedSidebarItem: CrawlBarSettingsSidebarItem?
    @Published var statuses: [CrawlAppID: CrawlAppStatus] = [:]
    @Published var installations: [CrawlAppID: CrawlAppInstallation] = [:]
    @Published var isRefreshing = false
    @Published var isInstallingCLI = false
    @Published var appActionMessage: String?
    @Published var runningActions: [CrawlAppID: String] = [:]
    @Published var actionMessages: [CrawlAppID: String] = [:]
    @Published var recentResults: [CrawlAppID: CrawlCommandResult] = [:]
    @Published var lastError: String?
    @Published var manifestDiagnostics: [CrawlManifestDiagnostic] = []
    @Published var isLoading = false
    @Published var manifestDirectories: [String] = ["~/.crawlbar/apps"]

    var refreshTask: Task<Void, Never>?
    var loadTask: Task<Void, Never>?
    var pendingSaveTask: Task<Void, Never>?
    var refreshGeneration = UUID()
    var loadGeneration = UUID()
    var recentResultsGeneration = UUID()
    var hasLoadedSnapshot = false
    var clearedNativeSecretIDsByAppID: [CrawlAppID: Set<String>] = [:]
    let store = CrawlBarConfigStore()
    let registry = CrawlAppRegistry()
    let runner: CrawlCommandRunner
    let statusService: CrawlStatusService
    let nativeConfigStore = CrawlNativeConfigStore()
    let installer = CrawlInstaller()
    let logStore = CrawlActionLogStore()

    var selectedAppID: CrawlAppID? {
        get {
            guard case let .crawler(id) = self.selectedSidebarItem else { return nil }
            return id
        }
        set {
            self.selectedSidebarItem = newValue.map(CrawlBarSettingsSidebarItem.crawler)
        }
    }

    init(loadImmediately: Bool = true) {
        let runner = CrawlCommandRunner()
        self.runner = runner
        self.statusService = CrawlStatusService(runner: runner)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(Self.statusesDidChange(_:)),
            name: .crawlBarStatusesDidChange,
            object: nil)
        if loadImmediately {
            self.load()
        } else {
            self.selectedSidebarItem = .general
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var sidebarSelectionIsValid: Bool {
        switch self.selectedSidebarItem {
        case .general:
            true
        case .crawler(let id):
            self.apps.contains { $0.id == id }
        case nil:
            false
        }
    }

}
