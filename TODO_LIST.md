<!-- TODO_LIST.md — living document. DONE items are REMOVED and logged in
     CHANGELOG.md. For long-term vision and unrefined ideas, use ROADMAP.md. -->

# TODO List

> Short-term, actionable, bounded work items, verified against the actual
> code. For long-term vision and unrefined ideas, use ROADMAP.md. Items are
> ranked by impact. Status is verified, not assumed.

## Status legend

| Status           | Meaning                                                     |
| ---------------- | ----------------------------------------------------------- |
| 🔴 `TODO`        | Not started. Needs doing.                                   |
| 🟡 `IN_PROGRESS` | Actively being worked on.                                   |
| 🔵 `BLOCKED`     | Cannot proceed, external dependency or decision needed.     |
| 🟢 `DONE`        | Completed. Remove from this list and log in `CHANGELOG.md`. |

## High Impact

| Task                                                                             | Status       | Impact | Effort | Evidence                                                                                                                                 |
| ------------------------------------------------------------------------------- | ------------ | ------ | ------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| v0.1.1 patch tag decision (two lib fixes + CI-verified state; owner question g3) | 🔵 `BLOCKED` | High   | 10min  | Owner call; the release content exists (CHANGELOG bullet list), the tag does not                                                         |

## Medium Impact

| Task                                                    | Status       | Impact | Effort | Evidence                                                                                                                                                    |
| ------------------------------------------------------- | ------------ | ------ | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Identify the owner/generator of `.config/metadata.yaml` | 🔵 `BLOCKED` | Low    | 10min  | Report §g Q3 (unanswered): created 2026-11-12 14:23, `tags: []`, landed in auto-commit 229f441 — which tool owns it, and may docs sessions populate `tags`? |
| Dependabot reviewers/assignees config                   | 🔵 `BLOCKED` | Low    | 5min   | Owner preference unknown; `.github/dependabot.yml` works without it                                                                                         |

## Shipped 2026-11-13 (logged in CHANGELOG.md)

- `nix flake update` manual flow — lock refreshed (all tips already current),
  full gates re-proven: `nix flake check -L` (5 VMs + all pure checks),
  aarch64 eval pass, parity 22/22, mutation harness 63/63.
- docs-gates pinned as a flake input (locked rev `eb2fa6bc`) + devShell and
  `nix run .#docs-gates` passthrough — the floating `github:` ref is gone.
- SystemNix `flake.lib` anomaly — root-caused (simple `lib:` parameter vs
  attrset-wrapper call shape) and FIXED SystemNix-side; annotation updated.
- Negative harness per-group transcripts (failure surfacing without parallel
  interleaving; proven with a forced failure).
- boot-mirror diff-gate eval pin + `diffgate-stripped` mutation leg (found and
  closed a consistent-mutation phantom-green trap on the way).
- Parity-diff standing cadence documented in `check.yml` + CI notice reminder.
