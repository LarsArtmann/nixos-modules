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

| Task                                                                 | Status        | Impact | Effort | Evidence                                                                                                        |
| -------------------------------------------------------------------- | ------------- | ------ | ------ | --------------------------------------------------------------------------------------------------------------- |
| docs-gates adoption: `.docs-gates.json` in-repo + baseline green (Process) | 🔴 `TODO` | Med | 30min | Report §f item 13; `nix run github:Artmann-Technologies/docs-gates -- run .` works — baseline FAILs only on the 2 unharvested §f items (this row + the next) |
| Re-run docs-health VERIFY after the pareto execution lands → establish post-fix baseline score (Process) | 🔴 `TODO` | Med | 90min | Report §f item 26; re-scores Accuracy/Fitness against the new baseline after T1-T14 |

## Medium Impact

| Task                                                                | Status    | Impact | Effort | Evidence                                              |
| ------------------------------------------------------------------- | --------- | ------ | ------ | ----------------------------------------------------- |
| Fix stale GW-source comment in `watch.sh`                           | 🔴 `TODO` | Med    | 15min  | `modules/wifi-failover/watch.sh:26-27` says the unit injects GW from `config.networking.local.gateway` (SystemNix-era coupling); this repo injects from `services.wifi-failover.gateway` / `networking.defaultGateway` (`modules/wifi-failover/default.nix:37-44`). Coordinate with the SystemNix parity diff — the copies are forked-during-migration |
| Run the pure-eval checks on aarch64-linux too                       | 🔴 `TODO` | Med    | 30min  | `flake.nix` gates ALL 3 eval-contracts + `module-list` behind `system == "x86_64-linux"`; all are pure eval and portable |
| Marker-stability pass over archived strikethroughs                  | 🔴 `TODO` | Med    | 15min  | `docs/status/archived/2026-11-12_docs-overhaul.md` was gated pre-move but no dprint pass + re-gate ran (annotate → check-rows → format → check-rows canon) |

## Low Impact

| Task                                                             | Status    | Impact | Effort | Evidence                                                                  |
| ---------------------------------------------------------------- | --------- | ------ | ------ | ------------------------------------------------------------------------- |
| Surface the negative harness as a flake app or devShell command  | 🔴 `TODO` | Low    | 30min  | `tests/negative/run.sh` is invoked by raw path only (`flake.nix` has no app; no devShell exists) |
| Force a fresh (non-cached) wifi-failover-vm run                   | 🔴 `TODO` | Low    | 15min  | This session's `nix flake check` green for `wifi-failover-vm` was store-substituted (inputs unchanged); a cache-busted rebuild re-proves the VM leg |
