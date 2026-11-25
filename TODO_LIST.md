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

| Task                                                                                                                                                                                                 | Status       | Impact | Effort | Evidence                                                                                                                                                                                                                                                                                                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ------ | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| v0.1.1 / 0.2.0 tag decision (two lib fixes + the modloc CLI; owner questions g3 of 11-24 and g of 11-25)                                                                                             | 🔵 `BLOCKED` | High   | 10min  | Owner call; the release content exists (CHANGELOG bullet list), the tag does not. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.16                                                                                                                                                                                                             |
| Prove the modloc fix live on evo-x2: bare `modloc` in webphone prints the two module rows and `/run/current-system` equals the newest `system-N-link`; then trash the `~/.cache/modloc-fix/` scratch | 🔵 `BLOCKED` | High   | 5min   | Waits for the foreign `nix run .#deploy` started 01:02:46 (the Tctl, PSI and quiescence gates decide a re-fire). nixos-modules `05b6917` is on origin; the SystemNix lock is at `210eced` (committed) / `05b6917` (working tree); live PATH was still `kslmqjq6-modloc` at 01:03. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.1, §f.2, §f.29 |

## Medium Impact

| Task                                                                                                                                                                                                                 | Status       | Impact | Effort | Evidence                                                                                                                                                                     |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ------ | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| modloc polish pass: rename `usage_error` to `die_usage` and `other` to `other_lang`, split `no such directory` from `not a directory`, add a spaced-path contract leg, re-run the contract + `modloc` negative group | 🔴 `TODO`    | Medium | 30min  | `modules/modloc/modloc.sh`, `tests/modloc-contract.nix`. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.3                                |
| Watch CI for nixos-modules `210eced` and `05b6917` (VM legs, `lib-eval`, the remaining contract checks: first full run on this tree)                                                                                 | 🔴 `TODO`    | Medium | 15min  | `gh run list -R LarsArtmann/nixos-modules`; two runs `in_progress` at 01:02. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.4, §f.6      |
| Upstream scc issue draft (`github-voice`) plus the `scc --by-module` design note (marker set, nearest wins, formats)                                                                                                 | 🔵 `BLOCKED` | Medium | 1h     | Owner green-light for the issue-first PR (11-24 report g.2); nothing filed. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.17, §f.30     |
| CI path filters: skip the VM battery on docs-only pushes                                                                                                                                                             | 🔵 `BLOCKED` | Medium | 30min  | Owner call (11-25 g.2); every daemon push runs `nix flake check -L` including the VMs. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.15 |

## Low Impact

| Task                                                                                                                                              | Status       | Impact | Effort | Evidence                                                                                                                                                                         |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dependabot reviewers/assignees config                                                                                                             | 🔵 `BLOCKED` | Low    | 5min   | Owner preference unknown; `.github/dependabot.yml` works without it                                                                                                              |
| ANNOTATE the 08-58 modloc report: rows f.5/6/7/8/11/15/16/26 are done                                                                             | 🔴 `TODO`    | Low    | 15min  | docs-health ANNOTATE; closed by nixos-modules `e627571`…`210eced`. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.5                          |
| Negative legs for `-l` after the path and for a spaced path (mutations must stay shellcheck-clean)                                                | 🔴 `TODO`    | Low    | 20min  | `tests/negative/run.sh` group `modloc`. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.7                                                     |
| (repo: SystemNix) at the deploy: full `buildflow` battery + features-drift eval, FEATURES row + header re-stamp, CHANGELOG line for the fixed CLI | 🔴 `TODO`    | Low    | 30min  | 11-24 report f.12/f.14; docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.8, §f.19, §f.21                                                       |
| (repo: SystemNix) file or fix the `prune-done-todos.sh:126` buildflow finding                                                                     | 🔴 `TODO`    | Low    | 15min  | 11-24 report f.13 (verify pre-existence via `git log`); docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.20                                    |
| Report-location ruling for cross-repo sessions (report follows the edits vs the session's cwd repo)                                               | 🔵 `BLOCKED` | Low    | 1min   | Owner call (11-25 g.3): this session ran in SystemNix, every edit landed in nixos-modules. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.28 |
| modloc on more hosts (rpi3-dns)                                                                                                                   | 🔵 `BLOCKED` | Low    | 10min  | Probably no: desktop tool (11-24 report g.3). docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.18                                              |
| Reconcile `dprint.json`: CHANGELOG 2026-11-22 says deleted + gitignored, the file is tracked and not ignored                                      | 🔴 `TODO`    | Low    | 10min  | `git ls-files dprint.json` lists it; `git check-ignore dprint.json` prints nothing. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.27        |
| Fix the shellcheck SC2016 info at `tests/negative/run.sh:175`                                                                                     | 🔴 `TODO`    | Low    | 5min   | Escape the `$` in the sed expression; the file is not shellcheck-gated. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.26                    |
| Set `system.stateVersion` in the contract-check fixtures                                                                                          | 🔴 `TODO`    | Low    | 15min  | Every check eval prints the warning. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.24                                                       |
| Add `meta` to the flake `apps`                                                                                                                    | 🔴 `TODO`    | Low    | 5min   | `nix flake check` warns `lacks attribute 'meta'`. docs/status/2026-11-25_01-05_modloc-bare-run-root-cause-cli-hardening-status.md §f.25                                          |

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
