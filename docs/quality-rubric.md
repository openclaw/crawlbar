# CrawlBar Engineering Rubric

This rubric is for keeping CrawlBar small, native, and easy to change. It is
not a checklist that replaces judgment. Use it to find evidence that a change
reduces complexity, preserves behavior, and keeps the app's public contracts
clear.

CrawlBar is a macOS menu bar app for local crawler status and commands. The
best code for this repo is boring: small surface area, obvious names, native
macOS behavior, and no extra settings or abstractions before they pay for
themselves.

Useful references:

- Current CrawlBar source and tests.
- Apple documentation for menu bar extras, settings windows, menus, and
  accessibility.
- The Build macOS Apps guidance when an agent is building, packaging, launching,
  or visually verifying the app.

## Review Shape

Review both quantitative and qualitative evidence.

Quantitative evidence catches drift:

- Swift LOC by target and by file.
- Files over 400 LOC.
- Top-level type count per file.
- Public and package API declarations.
- SwiftPM products.
- Settings panels, toggles, fields, and command buttons.
- Single-use UI wrappers and helper types.
- AppKit, process, filesystem, and task references by target.

Qualitative evidence decides whether the metrics matter:

- Does this make the app easier to understand?
- Is there one obvious way to do the thing?
- Did the change reduce concepts, or only move them?
- Is the interface deeper and smaller, or shallow and broad?
- Would a future maintainer know where behavior belongs?
- Is any new knob backed by repeated user pain?
- Did the change preserve public package and user-facing contracts?

## Quantitative Baseline

Start substantial refactors with:

```sh
Scripts/quality_baseline.sh
```

That script is not a pass/fail gate. It is a baseline for review. A good
follow-up explains which number changed, why that number matters, and which
human-facing complexity was removed.

Suggested thresholds:

- No new Swift file over 400 LOC.
- Prefer 12 or fewer top-level types per file.
- Treat 20 top-level types in one file as a hard review stop.
- Keep shared UI primitives scarce; do not create one for a single call site.
- Keep Core free of SwiftUI and AppKit imports.
- Keep public/package API intentional and compatible with shipped SwiftPM
  products.

## Qualitative Gate

Use these lenses before calling a refactor better.

### Simplicity

Good:

- A maintainer can describe each file's responsibility in one sentence.
- The common path is visible without reading optional feature code.
- Settings show the small set of controls a user actually needs first.
- Optional or diagnostic behavior is visually and structurally secondary.

Bad:

- The app looks simpler only because code moved into more files.
- A simple status app needs many concepts before it can render a row.
- Settings expose implementation switches that users should not need.
- Multiple modules know the same sequencing policy.

### API Surface

Good:

- SwiftPM products remain compatible unless a maintainer explicitly accepts a
  breaking change.
- Public types are stable contracts: manifests, config, status, command
  results, and intentionally supported services.
- Internal helpers stay internal.
- Callers do not need to understand command assembly, redaction, status parsing,
  or config persistence details.

Bad:

- Removing a shipped product or public type inside a cleanup PR.
- Using public/package access because it is convenient.
- Passing large models through UI just to reach one field.
- Optional feature state becoming permanent app-wide API.

### Native macOS

Good:

- Menu bar shows current status and frequent actions.
- Settings owns fuller configuration and diagnostics.
- Standard menu items and shortcuts work.
- Accessibility exposes normal windows, menu items, labels, roles, and enabled
  state.

Bad:

- Custom AppKit bridges leak across unrelated SwiftUI code.
- The app needs special launch behavior that is not proven with the packaged
  bundle.
- Visual proof exists but AX cannot describe the UI.
- The menu becomes a dashboard.

### Product Boundary

Good:

- CrawlBar displays crawler status, paths, freshness, and available actions.
- Crawler CLIs own parsing, auth, archives, search, and source-specific privacy.
- CrawlBar uses crawler and source names directly.

Bad:

- CrawlBar invents new domain layers for data it does not own.
- UI names hide the crawler command or source app behind vague abstractions.
- Status views expose private raw content instead of counts, paths, and state.

### Dead Code And Optional Features

Good:

- Unused types, buttons, config fields, and status branches are measured before
  being kept.
- Feature removal is explicit when it changes user behavior.
- Optional capability UI appears only when the manifest/status proves it is
  relevant.

Bad:

- Keeping code because it might be useful later.
- Hiding a feature instead of deciding whether it belongs.
- Deleting behavior only to improve LOC metrics.
- Adding a setting for a rare maintainer workflow without proving it belongs in
  the app.

## Runtime Proof

For non-doc changes that touch app launch, menu, settings, packaging, command
execution, or status mapping, provide real proof. Prefer redacted terminal
output and a small screenshot or AX dump over a summary.

Useful commands:

```sh
swift build
swift run crawlbar-selftest
Scripts/package_app.sh
codesign --verify --deep --strict --verbose=2 dist/CrawlBar.app
dist/CrawlBar.app/Contents/Helpers/crawlbar config validate
```

Useful runtime observations:

- Packaged app launches.
- Menu bar item appears.
- Menu opens and contains expected groups.
- Settings opens from menu and keyboard shortcut.
- AX reports Settings as a normal window.
- Packaged helper runs from `Contents/Helpers`.

Do not include raw messages, contacts, tokens, private endpoints, phone numbers,
or account-specific content in proof.

## Complexity Reduction Order

When the code still feels too large, investigate in this order:

1. Dead code: unused types, unused helpers, unreachable branches, stale command
   mappings, stale status mappers.
2. User-facing settings: toggles, fields, panels, and buttons that are not part
   of the simple current path.
3. API surface: public/package declarations and SwiftPM products.
4. Feature concepts: install flows, remote execution, scheduling, snapshot
   publishing, cloud archive controls, and other optional capabilities.
5. UI primitives: one-off rows, panels, wrappers, and style variants.

Stop before removing functionality unless the behavior is dead, unreachable, or
explicitly approved for removal.

## Handoff

For a review or PR update, include:

- Baseline command and key numbers.
- Build/runtime proof or exact blocker.
- Public API compatibility status.
- Accepted severe findings and fixes.
- Deferred complexity reductions that need maintainer decision.
- Why the change is not just LOC/file-count gaming.
