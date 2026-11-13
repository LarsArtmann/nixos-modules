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
| -------------------------------------------------------------------------------- | ------------ | ------ | ------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `nix flake update` (manual flow: update + full gates + parity diff + harness)    | 🔴 `TODO`    | High   | 45min  | Lock rides 2026-11-12 unstable; policy (AGENTS) says manual flow once CI green — it is (run 43447887478)                                 |
| Pin docs-gates as a flake input instead of the floating `github:` ref            | 🔴 `TODO`    | High   | 20min  | The battery's rule drift already re-flagged archived reports once (2026-11-13); `nix run github:…` re-fetches whatever upstream is today |
| v0.1.1 patch tag decision (two lib fixes + CI-verified state; owner question g3) | 🔵 `BLOCKED` | High   | 10min  | Owner call; the release content exists (CHANGELOG bullet list), the tag does not                                                         |

## Medium Impact

| Task                                                                         | Status       | Impact | Effort | Evidence                                                                                                                                                    |
| ---------------------------------------------------------------------------- | ------------ | ------ | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| boot-mirror diff-gate harness leg (runtime bite for the `diff -r` gate)      | 🔴 `TODO`    | Med    | 30min  | The VM leg pins the degradation assert; the diff-gate itself has no mutation leg (needs an eval-visible pin first — gate is runtime-only)                   |
| SystemNix `flake.lib` anomaly: `harden` closure loses `lib.genAttrs`         | 🔴 `TODO`    | Med    | 30min  | Flagged 2026-11-13 (pre-existing); outlives my commit message only if tracked — fix or annotate SystemNix-side                                              |
| Harness: per-group log files surfaced on failure (parallel interleaves)      | 🔴 `TODO`    | Med    | 15min  | `tests/negative/run.sh` parallel mode prints interleaved group output; 48 cases now                                                                         |
| devShell: docs-gates passthrough (run the battery without the floating ref)  | 🔴 `TODO`    | Med    | 15min  | `nix develop` lacks the battery; everyone re-types the github: ref                                                                                          |
| Parity diff standing cadence: workflow comment + reminder (cannot run in CI) | 🔴 `TODO`    | Med    | 10min  | `tests/parity/run.sh` needs the SystemNix sibling — document that boundary in `check.yml` comments                                                          |
| Identify the owner/generator of `.config/metadata.yaml`                      | 🔵 `BLOCKED` | Low    | 10min  | Report §g Q3 (unanswered): created 2026-11-12 14:23, `tags: []`, landed in auto-commit 229f441 — which tool owns it, and may docs sessions populate `tags`? |
| Dependabot reviewers/assignees config                                        | 🔵 `BLOCKED` | Low    | 5min   | Owner preference unknown; `.github/dependabot.yml` works without it                                                                                         |
