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

## Medium Impact

| Task                                                                | Status    | Impact | Effort | Evidence                                              |
| ------------------------------------------------------------------- | --------- | ------ | ------ | ----------------------------------------------------- |
| Re-run docs-health VERIFY after the pareto execution lands → establish post-fix baseline score (Process) | 🔴 `TODO` | Med | 90min | Report §f item 26; re-scores Accuracy/Fitness against the new baseline after T1-T14 |
| Verify CI first run (workflow shipped, unexecuted)                  | 🔴 `TODO` | Med    | 15min  | `.github/workflows/check.yml` exists; FEATURES carries the row honestly 🟡 until a real GitHub run lands — flip on first green run |
| Apply the parseMemoryBytes bare-byte fix to the SystemNix fork       | 🔵 `BLOCKED` | Med | 30min | External repo: SystemNix's `lib/systemd.nix` copy still crashes on bare-byte MemoryMax (fix landed here 2026-11-12; CHANGELOG documents the divergence) |
| Absorb or bless the watch.sh comment divergence in the SystemNix parity diff | 🔵 `BLOCKED` | Low | 15min | Comment-only divergence (GW-source wording) landed here 2026-11-12; the SystemNix copy keeps the old (locally-true) comment — the standing parity diff (ROADMAP theme 1) must absorb it |
| Identify the owner/generator of `.config/metadata.yaml`             | 🔵 `BLOCKED` | Low | 10min | Report §g Q3 (unanswered): created 2026-11-12 14:23, `tags: []`, landed in auto-commit 229f441 — which tool owns it, and may docs sessions populate `tags`? |
