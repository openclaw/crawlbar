---
written_by: ai
---

# AGENTS.md

This file governs work in this repository.

## Read Order

For non-trivial CrawlBar work, start with:

1. `README.md`
2. `docs/control-protocol.md`
3. `docs/quality-rubric.md`
4. `docs/ui-rules.md`

## CrawlBar Boundary

CrawlBar is a native macOS menu/settings control plane for local source
crawlers. It discovers crawler manifests, maps crawler status/actions to UI and
CLI controls, runs configured crawler commands, and stores local CrawlBar
configuration.

CrawlBar should stay on the crawler control boundary. Source crawlers own source
archives, auth/session handling, parsing, search/open/evidence, raw schemas,
and source-specific privacy policy. Avoid adding higher-level synthesis,
cross-source interpretation, dashboards, or background daemon behavior unless a
maintainer explicitly accepts that product direction.

## Engineering Review

Use `docs/quality-rubric.md` for architecture, API, macOS behavior, proof,
privacy, and complexity review. Use `docs/ui-rules.md` for SwiftUI composition
and shared UI primitives.

For substantial refactors, gather a baseline before changing code:

```sh
Scripts/quality_baseline.sh
```

Treat the baseline as evidence, not as a score to game. A smaller file count,
LOC count, or type count is useful only when the change also reduces concepts,
API burden, settings clutter, or change amplification.

Review findings are most useful when they include:

```text
axis:
severity:
evidence:
recommended_fix:
proof_needed:
```

## Engineering Preferences

Prefer boring code with one obvious place for each responsibility.

- Keep new Swift files under roughly 400 LOC.
- Avoid grab-bag files with many unrelated top-level types.
- Keep `CrawlBarCore` free of AppKit and SwiftUI.
- Preserve shipped SwiftPM products and public APIs unless a maintainer accepts
  a breaking change.
- Keep AppKit escapes narrow and local to app/window/menu boundaries.
- Treat new settings, modes, scripts, feature flags, and adapters as design
  debt unless there is repeated evidence they are needed.
- Treat removal of user-visible functionality as a product decision, not a
  metrics cleanup.

## UI Design System

CrawlBar UI work must use a minimal native macOS design system instead of
one-off view styling.

- Check Apple HIG guidance and the relevant Build macOS Apps guidance before
  adding or changing visible settings, menu, window, button, drag-and-drop, or
  permission UI.
- Keep shared UI primitives to about 8-12 total. Add a new shared primitive only
  when it replaces repeated visual grammar or encodes a stable CrawlBar-wide
  concept.
- Do not create a new card, row, badge, button, callout, icon treatment, or
  layout style for each feature. Feature views should compose existing settings
  primitives such as panels, rows, facts, status views, and issue/help surfaces.
- Do not scatter magic numbers through feature views. Put recurring spacing,
  sizing, corner, and control metrics in the settings design tokens or reuse
  native SwiftUI/AppKit control sizing.
- Prefer native controls and system behavior. Custom UI must justify why
  standard macOS components are insufficient and must preserve accessibility,
  keyboard, pointer, and appearance behavior.
- Before handoff, review the UI diff against `docs/ui-rules.md`, the HIG, and
  the anti-slop/Ousterhout question: did this reduce concepts and visual
  grammar, or only add another special case?

## Proof

For changes touching app launch, packaging, menu behavior, settings behavior,
command execution, status mapping, or public contracts, include current proof.
Use the smallest useful subset:

```sh
swift build
swift run crawlbar-selftest
Scripts/quality_baseline.sh
Scripts/package_app.sh
codesign --verify --deep --strict --verbose=2 dist/CrawlBar.app
dist/CrawlBar.app/Contents/Helpers/crawlbar config validate
```

When UI behavior matters, prefer packaged-app proof plus an AX dump or
screenshot. Avoid claiming native macOS behavior that was only tested by
launching the raw SwiftPM executable.

## Privacy

Keep proof and docs to paths, counts, status, capabilities, and redacted command
output. Do not include raw messages, contacts, phone numbers, message bodies,
mail bodies, GPS coordinates, tokens, private endpoints, or account-specific
content unless a maintainer explicitly asks for it and the task requires it.
