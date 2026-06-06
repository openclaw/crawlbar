---
written_by: ai
signal: ai-synthesis
source: Josh alignment in CrawlBar Codex thread and /Users/josh/code/crawlers/AGENTS.md
editing: ai-generated
truth_status: proposed_for_josh_acceptance
---

# AGENTS.md

This file governs `/Users/josh/code/crawlers/crawlbar`.

Read the parent `/Users/josh/code/crawlers/AGENTS.md` first. For CrawlBar work,
also read:

1. `README.md`
2. `docs/control-protocol.md`
3. `docs/quality-rubric.md`
4. `docs/ui-rules.md`

## CrawlBar Boundary

CrawlBar is a native macOS menu/settings control plane for local source
crawlers. It discovers crawler manifests, maps crawler status/actions to UI and
CLI controls, runs configured crawler commands, and stores local CrawlBar
configuration.

Do not turn CrawlBar into a graph layer, ontology layer, dashboard, daemon, or
cross-source synthesis layer. Source crawlers own source archives, auth/session
handling, parsing, search/open/evidence, raw schemas, and privacy policy.

## Review Standard

All non-trivial CrawlBar code, UI, or architecture work must be reviewed against
`docs/quality-rubric.md`. UI decomposition and visual primitive work must also
be reviewed against `docs/ui-rules.md`.

Start substantial review or refactor work with:

```sh
Scripts/quality_baseline.sh
```

Review agents and ClawSweeper-style reviewers should report findings with:

```text
axis:
severity:
evidence:
recommended_fix:
proof_needed:
```

Do not accept LOC reduction, extra files, screenshots, or green builds alone as
completion proof. Completion requires the proof named in the active goal and
the relevant rubric axes.

## Session Goals

When setting a CrawlBar session goal, use the `session-goal-writer` skill and
derive success criteria from `docs/quality-rubric.md`.

The goal must say:

- which rubric axis or behavior the session improves;
- current evidence and known failures;
- unacceptable drift and bad proxies;
- proof commands or runtime observations;
- review lenses to run before handoff;
- exact completion proof.

Keep implementation state in an ExecPlan when the work is multi-step. Keep
architecture rationale in an RFC/ADR if the decision should survive beyond the
session. Keep CTO briefings concise and decision-grade.
