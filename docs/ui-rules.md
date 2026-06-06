---
written_by: ai
---

# CrawlBar UI Rules

These rules keep CrawlBar's SwiftUI code native-first, small, and composable.
They are a review rubric for UI refactor work, not a new framework.

Use this together with `docs/quality-rubric.md`. That file covers architecture,
API boundaries, native macOS behavior, proof, privacy, and review loops. This
file covers the smaller UI design-system contract.

Metrics are necessary but not sufficient. A refactor slice only counts as
progress if it removes duplicated visual grammar or makes a product boundary
clearer. LOC and type-count improvements alone do not count.

## Design System Contract

CrawlBar should have 8-12 shared UI primitives total. Shared primitives may
encode stable visual vocabulary:

- app icon
- status dot/pill
- panel
- detail section
- fact row
- control row
- switch row
- metric row
- empty state
- inline issue
- text formatters

Do not add a shared UI primitive unless it replaces repeated styling in 2+
places or encodes a stable CrawlBar-wide concept.

Shared UI must not mention crawler names, command names, settings workflows,
menu workflows, installation logic, or app-specific behavior.

Shared UI primitives should stay deep, not broad. Do not hide feature-specific
logic behind a primitive with many boolean flags or style variants. If a
primitive needs more than 2-3 visual variants, stop and review the boundary.

Shared UI primitives must not accept `CrawlAppConfig`, `CrawlAppManifest`,
crawler IDs, or command names unless the primitive is explicitly CrawlBar-wide,
such as an app icon or status view.

## Feature Composition

Feature views compose shared primitives. They may arrange crawler-specific
content, but should not define their own panel, card, row, status, or issue
styling.

Feature-local components live under their feature folder, such as `Settings/`
or `Menu/`. They are allowed when they hide cohesive product complexity and
keep the root scene easier to read.

Do not reward-hack the shared primitive cap by recreating panel, card, row,
status, or issue styling inside feature files. Feature files arrange product
content; shared primitives own visual grammar.

## File Metrics

- New UI files stay under 400 LOC.
- Prefer 12 or fewer top-level UI types per file.
- Treat 20 top-level types per file as a hard cap.
- Large existing UI files should shrink over time unless there is a stated
  reason.
- A maintainer should be able to name what each file owns in one sentence.
- Avoid giant computed view fragments. If a `body` or view helper grows beyond
  roughly 80-120 LOC, extract a named feature component instead of hiding the
  complexity inside one type.

## State Boundaries

- One scene or feature model owns scene state.
- Rows and panels receive explicit values, bindings, and callbacks.
- Do not create a view model per tiny row.
- Views do not own process, filesystem, config, or command effects.
- AppKit bridges stay narrow and do not leak through unrelated SwiftUI layers.

## Review Checklist

Before finishing a UI refactor slice:

- Did this reduce concepts, or only move lines?
- Did any new type become a one-off wrapper?
- Would this change still look good if LOC and type count were hidden?
- What boundary did this extraction improve in one sentence?
- Are feature views composing shared primitives?
- Is visual grammar centralized?
- Can a maintainer find panel, row, and status styling immediately?
- Would adding a crawler require product composition, not new visual primitives?
