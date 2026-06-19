# Changelog

## Unreleased

### Changes

- Add Apple Photos as a coming-soon built-in crawler with read-only status, initialization, search, and platform-native storage paths.

### Fixes

- Install OpenClaw crawler apps from the current Homebrew tap instead of legacy formulas that lag released versions.

## v0.3.0 - 2026-06-09

### Changes

- Redesign the menu bar UI with RepoBar-style native rich menu rows, branded crawler icons, status summaries, and tabbed settings.
- Replace crawler detail tabs in Settings with one native scrolling detail page grouped into status, data, sync, and configuration sections.
- Improve app responsiveness by caching repeated config, manifest, binary lookup, native app, formatter, and icon work while reducing status refresh task overhead.
- Open Settings immediately by moving manifest, binary, config, and recent-log loading off the main actor.
- Use native switch-style controls for crawler boolean settings.
- Replace the generated app icon with a richer image-generated CrawlBar icon and use it for both runtime and packaged app icons.
- Enable Google (`gog`) and WhatsApp (`wacli`) crawler entries with real status, doctor, search, and install wiring.
- Fix Settings sidebar clicks so selecting crawler rows reliably updates the detail pane, and show the active sidebar selection clearly.
- Normalize crawler command environments with `HOME` so launchd-started menu bar status matches terminal status for tools like `gog`.
- Add Telecrawl as a built-in Telegram crawler with status, import, doctor, search, privacy, install metadata, and branded menu icon support.
- Make menu and settings opening faster by caching rendered crawler icons, coalescing status menu rebuilds, and avoiding synchronous refresh work during settings presentation.
- Add CrawlBar support for Cloudflare remote crawler archives, including built-in `remote status`, `remote archives`, and compressed SQLite `cloud publish` actions for `gitcrawl` and `discrawl`.
- Surface Cloudflare D1/R2 archive status, remote archive metadata, and gzip chunked SQLite bundle details in normalized status JSON and the settings UI.
- Bundle real macOS app icons for GitHub Desktop, Slack, Discord, Notion, WhatsApp, and Granola crawler rows.
- Guard source and packaged brand icon assets in CI so crawler logos cannot regress silently. Thanks @vincentkoc.

## v0.2.2 - 2026-05-22

### Fixes

- Fix crawler discovery from the macOS app by normalizing PATH with common Homebrew, MacPorts, and user-local CLI locations before resolving or running crawler commands. Thanks @mbelinky.

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
