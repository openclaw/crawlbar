---
written_by: ai
signal: ai-synthesis
source: Josh alignment in CrawlBar Codex thread; CrawlBar source inspection; Build macOS Apps guidance; Apple MenuBarExtra, Settings, HIG Menus, HIG Settings, and NSAccessibilityProtocol docs
editing: ai-generated
truth_status: proposed_for_josh_acceptance
---

# CrawlBar Quality Rubric

This is the engineering review contract for CrawlBar. Use it with
`docs/ui-rules.md`: this file covers app quality, architecture, API boundaries,
proof, privacy, and review loops; `ui-rules.md` covers the smaller UI design
system.

CrawlBar's product boundary is simple: a professional native macOS control
plane for local source crawlers. Source crawlers own source parsing, archives,
auth/session handling, search/status/open/evidence, and privacy policy.
CrawlBar discovers crawler contracts, displays status, routes actions, and
keeps local configuration legible.

## How Reviewers Use This

Review agents, implementation agents, and ClawSweeper-style reviewers should
review against axes, not vibes. A finding should include:

```text
axis: one rubric axis below
severity: P0, P1, P2, or P3
evidence: file/line, command output, screenshot, AX dump, or exact behavior
recommended_fix: smallest change that improves the axis
proof_needed: command, runtime observation, screenshot, or reviewer check
```

Severity:
- `P0`: breaks the product boundary, privacy, build/run, or basic usability.
- `P1`: makes the app materially harder to maintain, observe, or trust.
- `P2`: local slop, unclear responsibility, one-off UI, or avoidable API
  surface that will compound.
- `P3`: polish, naming, or cleanup that is useful but not blocking.

Completion rule: no accepted P0/P1 findings remain. P2 findings are either
fixed, explicitly deferred with a reason, or turned into the next slice. P3
findings do not block if the proof gates pass.

## Gradient Descent Protocol

Every substantial CrawlBar session should:
1. Measure the current baseline.
2. Pick the highest-leverage accepted axis failure.
3. Make the smallest change that improves that axis without regressing another.
4. Re-run the relevant proof gates.
5. Run an adversarial review pass against this rubric.
6. Stop when no accepted severe findings remain for the slice.

Do not optimize a single metric. File size, type count, screenshots, build
success, and pretty UI are proxies. Progress means reduced cognitive load,
clearer ownership, fewer concepts, better native behavior, stronger proof, or a
smaller real API.

Baseline command:
```sh
Scripts/quality_baseline.sh
```

A baseline is not a pass/fail by itself. It is the starting point reviewers use
to choose the worst accepted axis failure and to prove a later slice improved
the codebase instead of rearranging it.

## Scorecard Artifact

Every review or handoff should include this compact scorecard:
```text
baseline: command/path/date used
build_proof: pass/fail/blocker
runtime_proof: AX, screenshot, log, or blocker
P0/P1: none, or listed with owner/fix
P2: fixed, deferred, or next slice
axis_changed: rubric axis improved
anti_gaming_check: why this is not just LOC/files/build/screenshot progress
next_slice: highest-leverage remaining accepted finding
```

## Session Goal Contract

When using `session-goal-writer` for CrawlBar work, encode the slice using this
shape:

- User vision: make CrawlBar more professional, native, source-backed, and
  maintainable.
- North star: a local macOS control plane for source crawlers, not a synthesis
  layer.
- Current slice: name the exact axis or behavior being improved.
- Current state: include live metrics, known failing proof, and dirty-worktree
  caveats.
- Unacceptable drift: LOC-only cleanup, one-off UI, speculative abstractions,
  extra modes, crawler behavior changes, or unproven UI claims.
- Success criteria: name outcome, evaluator, evidence, anti-gaming rule, stop
  condition, and blocker condition.
- Review proof: require at least architecture, API, UI, native macOS,
  observability, privacy, and anti-slop lenses when relevant.
- Completion proof: current build/runtime/review evidence, not intent.

## Axis 1: Product Boundary

Good:
- CrawlBar is a menu/settings control plane for crawler commands.
- It uses source-native crawler names and command contracts.
- It shows counts, status, freshness, capability, paths, and actions without
  becoming a graph, ontology, dashboard, or personal-synthesis layer.

Bad signals:
- New concepts that belong in Lifecrawler or a downstream synthesis layer.
- UI or API names that hide source-native crawler names.
- CrawlBar interpreting private source data beyond status/control needs.

Measure:
- Search new names for invented ontology or umbrella terms.
- Check action/status fields against manifests and crawler CLIs.
- Verify UI/log output contains no raw private content.

## Axis 2: Native macOS Behavior

Good:
- Menu bar is for quick state and frequent actions.
- Settings is the full management surface.
- `Settings...` and `Command-Comma` open settings.
- Menu labels are concise, title case, grouped, and use ellipsis when more
  input or a window is needed.
- Settings avoid asking for setup the app can detect.

Bad signals:
- Menu becomes a dashboard.
- Settings is unreachable or behaves like an arbitrary custom window.
- Native app availability is treated as a hidden preference instead of
  detected state.
- Long or unclear menu labels.

Measure:
- AX dump for menu names, roles, enabled state, and order.
- AX or visual proof that Settings opens from menu and keyboard.
- Visual proof across the main settings window.

Sources:
- Apple `MenuBarExtra`: persistent menu bar access to common functionality.
- Apple `Settings`: standard settings scene and keyboard shortcut behavior.
- Apple HIG Menus and HIG Settings.

## Axis 3: Observability And Proof

Good:
- A reviewer can prove build, launch, menu, settings, and core actions from
  commands and observations.
- AX can read names, roles, values, enabled states, and trigger key actions.
- Screenshots or Computer Use verify rendering when available.
- Logs explain menu/settings/action events without leaking private data.

Bad signals:
- "Looks fine" without screenshot or AX evidence.
- Screenshots without behavior proof.
- AX item names are missing or custom rows are unreadable.
- Logs are silent during user-visible actions that need diagnosis.

Measure:
```sh
swift build
swift run crawlbar-selftest
Scripts/package_app.sh
codesign --verify --deep --strict --verbose=2 dist/CrawlBar.app
pgrep -fl CrawlBar
log show --last 10m --predicate 'subsystem == "com.vincentkoc.CrawlBar"'
```

Use AX scripts to press the menu extra, dump menu item names/roles/enabled
states, open Settings, and dump the settings window hierarchy.

## Axis 4: Architecture And DAG

Good:
- `CrawlBarCore` owns data contracts, manifest/config/status/action models,
  runners, registries, redaction, and source-neutral services.
- `CrawlBar` owns AppKit, SwiftUI, windows, menu bar, settings UI, and
  presentation state.
- `CrawlBarCLI` owns argument parsing and command output only.
- `CrawlBarSelfTest` owns executable contract checks only.
- Dependencies point inward to Core; Core does not import AppKit or SwiftUI.

Bad signals:
- AppKit or SwiftUI in Core.
- Process, filesystem, config persistence, or crawler command policy embedded
  in view bodies.
- Menu and settings features importing each other without a clear reason.
- Services exposed publicly because a boundary is leaky.

Measure:
```sh
rg -n 'import (AppKit|SwiftUI)' Sources/CrawlBarCore
rg -n 'Process\\(|FileManager\\.|NSWorkspace|NSApp|NSWindow|NSMenu|Task\\s*\\{' Sources
rg -n '^(public|package) ' Sources/CrawlBarCore
```

Review whether every import and every public/package declaration has a real
caller and a real contract.

## Axis 5: Deep Modules And API Surface

Good:
- Public/package API exposes stable contracts, not implementation convenience.
- Interfaces are small, explicit, and source-native.
- Sequencing and policy are hidden inside deep modules.
- Callers should not need to know how status, manifests, redaction, or command
  arguments are assembled.

Bad signals:
- Boolean-heavy shallow helpers.
- Many tiny services that merely pass through to each other.
- Package visibility used to avoid designing a boundary.
- Optional extras exposed as first-class knobs before repeated pain exists.

Measure:
- Count public/package declarations and justify them.
- For each service, ask what complexity it hides from callers.
- Review call sites for repeated policy or command assembly.

## Axis 6: State And Effects Ownership

Good:
- One scene or feature model owns scene state.
- Rows/panels receive explicit values, bindings, and callbacks.
- Effects live in model/service/action layers, not low-level UI components.
- Async tasks have clear owner, cancellation, and stale-result behavior.

Bad signals:
- A view owns process execution, config writes, filesystem operations, or
  crawler policy.
- Many tiny row view models.
- Notification, timer, task, and reload logic scattered across unrelated files.
- State mutation hidden behind broad closures with unclear side effects.

Measure:
- Search for effects in SwiftUI files.
- Review async tasks for ownership and cancellation.
- Check whether a new behavior changes one file or many unrelated files.

## Axis 7: UI System

Use `docs/ui-rules.md` as the detailed UI contract.

Good:
- 8-12 shared UI primitives total.
- New UI files stay under about 400 LOC.
- Prefer 12 or fewer top-level UI types per file; 20 is a hard smell.
- Feature views compose shared primitives instead of redefining visual grammar.

Bad signals:
- A "design system" where every object is its own primitive.
- Feature files recreating rows, cards, panels, issue banners, or status dots.
- Custom chrome fighting native macOS sidebar/detail behavior.

Measure:
```sh
find Sources -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head
find Sources -name '*.swift' -print0 | xargs -0 rg -n '^(struct|class|enum|protocol) '
```

## Axis 8: Manifest And Crawler Contracts

Good:
- Built-in and external manifests are the primary app model.
- Crawler-specific differences live in manifests or narrow adapters.
- CrawlBar can explain whether a crawler is available, configured, suggested,
  or unsupported from source-backed signals.

Bad signals:
- Hardcoded UI branching for a crawler when a manifest field would express it.
- Manifest fields added speculatively for one crawler without repeated need.
- CrawlBar assuming command names that drift from crawler CLIs.

Measure:
- Compare manifests against current crawler CLI help/status/metadata commands.
- Validate config and metadata through `crawlbarctl`.
- Review any crawler-specific code path for whether it should be manifest data.

## Axis 9: Reliability And Dev Lifecycle

Good:
- One obvious build/package/run path exists for the app.
- Dev does not require replacing Homebrew/system binaries.
- The packaged app contains resources, helper binary, bundle metadata, and
  signing expected by macOS.
- Runtime proof uses the packaged app, not only raw SwiftPM executables.

Bad signals:
- Manual command chains that differ per agent.
- Raw GUI executable launch used as product proof.
- Stale packaged app or helper binary.
- Build passes but packaged app cannot be observed.

Measure:
- `swift build`
- `swift run crawlbar-selftest`
- `Scripts/package_app.sh`
- `codesign --verify --deep --strict --verbose=2 dist/CrawlBar.app`
- `pgrep -fl CrawlBar`
- Helper CLI `--help` and `config validate`.

## Axis 10: Privacy And Redaction

Good:
- UI, logs, screenshots, and CLI output use paths, counts, status, capability,
  and aggregate summaries.
- Command output is redacted before persistence or UI display.
- Secrets are kept out of config and scrubbed from settings state.

Bad signals:
- Raw contacts, phone numbers, message bodies, mail bodies, GPS coordinates,
  tokens, or private reports in durable docs/logs/screenshots.
- Review output that includes private source content when capability/status
  would be enough.

Measure:
- Inspect action logs and screenshot/AX artifacts before sharing.
- Search for token-like/private fields in new outputs.
- Review secret config handling for both save and window close paths.

## Axis 11: Tests And Contract Checks

Good:
- Self-test covers manifest loading, command mapping, redaction, config, status
  mapping, and edge cases that are easy to regress.
- Runtime proof covers menu/settings behavior self-test cannot cover.
- Tests make behavior clearer instead of duplicating implementation.

Bad signals:
- Large tests that are hard to localize.
- Tests pass because they no longer cover the risky behavior.
- UI refactors without runtime proof.

Measure:
- `swift run crawlbar-selftest`
- Review self-test file size and cohesion.
- Add or split tests when a change touches shared contracts.

## Axis 12: Docs And Agent Operability

Good:
- Docs explain durable contracts, not volatile state.
- AGENTS points agents to the right contracts.
- Reviewers know what to measure and what counts as proof.
- Implementation state goes in an ExecPlan when needed, not in the rubric.

Bad signals:
- Duplicate overviews.
- Pointer stubs with no contract.
- Markdown created to look productive.
- Docs that freeze tactical guesses as requirements.

Measure:
- Check whether a new doc has one purpose and a real consumer.
- Check whether future agents can use it without thread context.
- Delete or consolidate stale docs when they lose purpose.

## Pre-Handoff Review Lenses

Before handoff, run these lenses and accept only findings grounded in evidence:
- Principal engineer: does the structure reduce change amplification?
- Ousterhout: are modules deep enough and interfaces narrow enough?
- Zen of Python: is there one obvious path and explicit naming?
- Native macOS: does it behave like a Mac menu/settings app?
- Accessibility: can AX read and drive key UI?
- Source discipline: are claims source-backed and source-native?
- Privacy: are private data and secrets absent from outputs?
- Anti-slop: did the change reduce concepts instead of moving lines?

Stop reviewing when no accepted severe findings remain and proof is current.
