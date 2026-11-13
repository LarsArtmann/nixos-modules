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

| Task                                                                         | Status       | Impact | Effort | Evidence                                                                                                                                                                                                                        |
| ---------------------------------------------------------------------------- | ------------ | ------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Identify the owner/generator of `.config/metadata.yaml`                      | 🔵 `BLOCKED` | Low    | 10min  | Report §g Q3 (unanswered): created 2026-11-12 14:23, `tags: []`, landed in auto-commit 229f441 — which tool owns it, and may docs sessions populate `tags`?                                                                     |
| Mark the SUPERB plan file EXECUTED (header note)                             | 🔴 `TODO`    | Low    | 5min   | `docs/planning/2026-11-12_22-04_*` lacks an executed-banner; readers must diff dates to learn all 18 tasks landed                                                                                                               |
| CHANGELOG [0.1.0] tag-ref link + version-bump flow                           | 🔴 `TODO`    | Low    | 15min  | Keep-a-Changelog links version headings to tag compares; the tag exists locally but the heading has no ref, and no doc says how 0.2.0 gets cut                                                                                  |
