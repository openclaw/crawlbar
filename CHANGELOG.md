# Changelog

## v0.2.1 - 2026-05-22

### Fixes

- Fix packaged app icon loading by resolving the SwiftPM resource bundle from installed app locations and failing packaging when the bundle is missing or empty. Thanks @mbelinky.

## v0.2.0 - 2026-05-20

### Changes

- Add the native CrawlBar menu bar app for local-first crawler status, refreshes, logs, settings, and packaged CLI access.
- Add built-in crawler manifests for GitHub, Slack, Discord, Notion, and Granola, with coming-soon entries for Google, WhatsApp, and X.
- Add branded crawler icons, including bundled Google, X, and Granola assets for offline app/package rendering.
- Add crawler detail tabs for Overview, Data, Sync, and Settings, with refresh, archive, binary, snapshot, and config state shown where relevant.
- Add local app packaging through `Scripts/package_app.sh`, including the `CrawlBar.app` bundle and embedded `crawlbar` helper.
- Add Homebrew source-build support for installing the app bundle and CLI together.

### Fixes

- Avoid macOS Keychain prompts during read-only status paths.
- Preserve native crawler secret semantics while still allowing CrawlBar-managed secrets to be cleared explicitly.
- Keep all-app query behavior searchable and route SQL/text queries to the right crawler capability.
- Surface crawler action failures instead of hiding them behind stale successful state.
- Normalize GitHub authentication failures as credential problems instead of raw request errors.
- Preserve useful current crawler data when refreshes fail.
- Hide successful exit-0 stdout noise in the latest-run summary.
- Remove window-level tooltips from the main app while keeping menu bar affordances usable.
- Hide empty snapshot remote details and avoid duplicating Data summaries in Overview.
- Show remote crawler stores for GitHub-backed archives.
- Write numeric crawler config values as numbers, fixing Graincrawl desktop-cache recovery after cache-version failures.

### Maintenance

- Add SwiftPM CI covering build, selftest, CLI smoke, app packaging, and packaged CLI smoke.
- Add a selftest suite for config normalization, metadata mapping, crawler failure semantics, query routing, and settings behavior.
- Add the control protocol documentation and example manifest for future crawler integrations.

## v0.1.0

- Initial local CrawlBar prototype.
