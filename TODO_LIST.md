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
| Verify CI first run (workflow shipped, unexecuted)                  | 🔴 `TODO` | Med    | 15min  | `.github/workflows/check.yml` exists; FEATURES carries the row honestly 🟡 until a real GitHub run lands — flip on first green run |
| Apply the parseMemoryBytes bare-byte fix to the SystemNix fork       | 🔵 `BLOCKED` | Med | 30min | External repo: SystemNix's `lib/systemd.nix` copy still crashes on bare-byte MemoryMax (fix landed here 2026-11-12; CHANGELOG documents the divergence) |
| Absorb or bless the watch.sh comment divergence in the SystemNix parity diff | 🔵 `BLOCKED` | Low | 15min | Comment-only divergence (GW-source wording) landed here 2026-11-12; the SystemNix copy keeps the old (locally-true) comment — the standing parity diff (ROADMAP theme 1) must absorb it |
| Identify the owner/generator of `.config/metadata.yaml`             | 🔵 `BLOCKED` | Low | 10min | Report §g Q3 (unanswered): created 2026-11-12 14:23, `tags: []`, landed in auto-commit 229f441 — which tool owns it, and may docs sessions populate `tags`? |
| Verify CI workflow action refs before first push                    | 🔴 `TODO` | Med    | 15min  | `.github/workflows/check.yml` pins `actions/checkout@v5` + `DeterminateSystems/nix-installer-action@v17` — existence/major-version correctness NOT verified against the marketplace this session |
| Add the options-json bite-proof leg                                 | 🔴 `TODO` | Med    | 30min  | `tests/options-json.nix` has only the positive proof; the header documents why no import-apply leg exists, but no leg at all proves the check itself fails when provenance breaks |
| lib-eval coverage for the 5 Class-B-only helpers                    | 🔴 `TODO` | Med    | 1-2h   | `mkSecretCheck`, `mkDesktopNotifyService`, `mkStateDir`, `wrapWithMemoryLimit`, `ioTier` (ioTier only transitively pinned by boot-mirror contract) have no direct lib-eval contracts |
| Document the mergeIt approximation in tests/lib-eval.nix           | 🔴 `TODO` | Low    | 10min  | The check merges serviceConfig via `evalModules` + `types.anything` — close to but not identical with the real NixOS option merge; the limitation is undocumented in the file |
| Investigate + document `--rebuild` semantics in AGENTS              | 🔴 `TODO` | Low    | 20min  | This session claimed "deterministic re-run" from `nix build --rebuild` output ("checking outputs of...") without verifying whether VMs actually re-executed; the one unambiguous fresh proof was the post-watch.sh full rebuild |
| Mark the SUPERB plan file EXECUTED (header note)                    | 🔴 `TODO` | Low    | 5min   | `docs/planning/2026-11-12_22-04_*` lacks an executed-banner; readers must diff dates to learn all 18 tasks landed |
| CHANGELOG [0.1.0] tag-ref link + version-bump flow                  | 🔴 `TODO` | Low    | 15min  | Keep-a-Changelog links version headings to tag compares; the tag exists locally but the heading has no ref, and no doc says how 0.2.0 gets cut |
