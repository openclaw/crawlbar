import Foundation

extension CrawlStatusMapper {
    func birdclawStatus(_ object: [String: Any], result: CrawlCommandResult) -> CrawlAppStatus {
        let transport = self.firstObject(["transport"], in: object) ?? object
        let installed = self.boolValue(["installed"], in: transport)
        let transportName = self.stringValue(["availableTransport"], in: transport)
            ?? self.stringValue(["available_transport"], in: transport)
        let statusText = self.stringValue(["statusText", "status_text", "summary", "message"], in: transport)

        let state: CrawlAppState = .current
        let summary = statusText ?? "birdclaw is ready"
        var warnings = transportName.map { ["Transport: \($0)"] } ?? []
        if installed == false, let statusText {
            warnings.append(statusText)
        }

        return CrawlAppStatus(
            appID: result.appID,
            state: state,
            summary: summary,
            warnings: warnings)
    }

    func birdStatusText(_ result: CrawlCommandResult) -> CrawlAppStatus {
        let output = result.stdout.nilIfBlank ?? result.stderr.nilIfBlank ?? ""
        let lowercased = output.lowercased()
        let hasAuthToken = lowercased.contains("[ok] auth_token")
            || lowercased.contains("auth_token:")
        let hasCSRFToken = lowercased.contains("[ok] ct0")
            || lowercased.contains("ct0:")
        let ready = lowercased.contains("ready to tweet")
            || (hasAuthToken && hasCSRFToken)
        let source = output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.lowercased().hasPrefix("source:") }
        let warningLines = output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let lowered = line.lowercased()
                return lowered.contains("[warn]") || lowered.hasPrefix("- ")
            }
            .map { line in
                line.replacingOccurrences(of: "[warn]", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .map { line in
                line.hasPrefix("- ")
                    ? String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : line
            }
            .filter { !$0.isEmpty && $0.lowercased() != "warnings:" }

        if ready {
            return CrawlAppStatus(
                appID: result.appID,
                state: .current,
                summary: source.map { "X cookies available via bird (\($0.dropFirst("source:".count).trimmingCharacters(in: .whitespacesAndNewlines)))" }
                    ?? "X cookies available via bird",
                warnings: warningLines)
        }

        return CrawlAppStatus(
            appID: result.appID,
            state: .needsAuth,
            summary: "X browser cookies not found",
            warnings: warningLines.isEmpty ? ["bird check did not find usable X cookies"] : warningLines)
    }

    func gogcliStatus(_ object: [String: Any], result: CrawlCommandResult, staleAfterSeconds _: Int?) -> CrawlAppStatus {
        if let accounts = object["accounts"] as? [[String: Any]] {
            let configuredAccount = accounts.first { account in
                self.boolValue(["valid"], in: account) != false
                    && ["oauth", "service-account", "service_account", "oauth+service-account", "oauth+service_account"].contains(
                        self.stringValue(["auth"], in: account)?.lowercased() ?? "")
            }
            let failedAccount = accounts.first { self.boolValue(["valid"], in: $0) == false }
            let failureSummary = failedAccount.flatMap { account in
                self.stringValue(["error", "hint", "email"], in: account)
            }
            return CrawlAppStatus(
                appID: result.appID,
                state: configuredAccount == nil ? .needsAuth : .current,
                summary: configuredAccount == nil ? failureSummary ?? "Google auth needs setup" : "Google auth configured")
        }

        if let status = self.statusValue(["status"], in: object), object["checks"] != nil {
            let checks = object["checks"] as? [[String: Any]]
            let readableTokens = checks?.first { check in
                self.stringValue(["name"], in: check) == "tokens"
                    && self.statusValue(["status"], in: check) == .current
            }
            let refreshErrors = checks?.filter { check in
                guard let name = self.stringValue(["name"], in: check) else { return false }
                return name.hasPrefix("refresh.") && self.statusValue(["status"], in: check) == .error
            } ?? []
            let warnings = checks?.compactMap { check -> String? in
                guard self.statusValue(["status"], in: check) != .current,
                      let name = self.stringValue(["name"], in: check)
                else { return nil }
                let detail = self.stringValue(["detail"], in: check)?.nilIfBlank
                return [name, detail].compactMap { $0 }.joined(separator: ": ")
            } ?? []
            if refreshErrors.isEmpty, let readableTokens {
                let detail = self.stringValue(["detail"], in: readableTokens)
                let summary = detail?.split(separator: " ").first.map { "\($0) Google OAuth accounts readable" }
                    ?? "Google OAuth accounts readable"
                return CrawlAppStatus(
                    appID: result.appID,
                    state: .current,
                    summary: summary,
                    configPath: self.gogcliConfigPath(fromChecks: checks),
                    warnings: warnings)
            }
            let failedCheck = checks?.first { check in
                self.statusValue(["status"], in: check) != .current
            }
            let failureSummary = failedCheck.flatMap { check in
                self.stringValue(["detail", "hint", "name"], in: check)
            }
            let mappedState = status == .current
                ? CrawlAppState.current
                : self.gogcliDoctorFailureState(failedCheck)
            return CrawlAppStatus(
                appID: result.appID,
                state: mappedState,
                summary: mappedState == .current ? "Google auth configured" : failureSummary ?? "Google auth needs setup",
                configPath: self.gogcliConfigPath(fromChecks: checks),
                warnings: warnings)
        }

        let account = self.firstObject(["account"], in: object) ?? [:]
        let config = self.firstObject(["config"], in: object) ?? [:]
        let serviceAccountConfigured = self.boolValue(["service_account_configured"], in: account) ?? false
        let state: CrawlAppState = serviceAccountConfigured ? .current : .needsAuth
        let summary = state == .current ? "Google service account configured" : "Google account needs auth"
        let warnings = self.boolValue(["exists"], in: config) == false
            ? ["gog config file not found"]
            : []
        return CrawlAppStatus(
            appID: result.appID,
            state: state,
            summary: summary,
            configPath: self.stringValue(["path"], in: config),
            warnings: warnings)
    }

    func gogcliDoctorFailureState(_ check: [String: Any]?) -> CrawlAppState {
        let name = check.flatMap { self.stringValue(["name"], in: $0) }?.lowercased() ?? ""
        return name.contains("config") ? .needsConfig : .needsAuth
    }

    func gogcliConfigPath(fromChecks checks: [[String: Any]]?) -> String? {
        checks?.first { self.stringValue(["name"], in: $0) == "config.path" }
            .flatMap { self.stringValue(["detail"], in: $0) }
    }
}
